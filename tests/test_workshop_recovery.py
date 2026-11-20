from base64 import b64decode
from copy import deepcopy
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import runpy
from shutil import copyfile
import subprocess
import sys
from tempfile import TemporaryDirectory
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from zipfile import ZipFile
from workshop_templates import load_template, team_limit


ROOT = Path(__file__).resolve().parents[1]
workshop = runpy.run_path(str(ROOT / "workshop"))
provision = workshop["provision"]
with patch.object(sys, "path", [str(ROOT / "dashboard"), *sys.path]):
    host = runpy.run_path(str(ROOT / "dashboard" / "host.py"))["handle"]
read_recording = host.__globals__["read_recording"]
dashboard_server = runpy.run_path(str(ROOT / "dashboard" / "server.py"))


class ProvisioningTest(unittest.TestCase):
    def test_guest_offers_only_the_host_key_guacamole_pins(self):
        create = workshop["create_guest"]
        calls = []
        with patch.dict(create.__globals__, {"incus": lambda *args: calls.append(args)}):
            create(1, {"run": "a" * 16, "image": "b" * 64}, "ssh-ed25519 test-key")
        cloud_init = next(arg for arg in calls[0] if arg.startswith("cloud-init.user-data="))
        files = json.loads(cloud_init.split("\n", 1)[1])["write_files"]
        sshd = next(file["content"] for file in files if file["path"].endswith("00-workshop.conf"))
        self.assertIn("HostKey /etc/ssh/ssh_host_ed25519_key\n", sshd)
        self.assertIn("HostKeyAlgorithms ssh-ed25519\n", sshd)

    def test_readiness_pins_the_key_offered_by_the_ssh_listener(self):
        wait = workshop["wait_for_ssh"]
        probes = []

        def incus(*args, **kwargs):
            self.assertIn("ssh-keyscan -T 2 -t ed25519 127.0.0.1", args[-1])
            return "127.0.0.1 ssh-ed25519 live-key"

        with patch.dict(wait.__globals__, {"incus": incus, "run": lambda *args, **_: probes.append(args)}):
            self.assertEqual(wait(1), "10.241.1.2 ssh-ed25519 live-key")
        self.assertEqual(probes[0][-2:], ("10.241.1.2", "22"))

    def test_reset_keeps_password_and_switches_screen_generation(self):
        team = {"login": "demo-aaaaaaaa-team-1-aaaaaaaa", "password": "unchanged", "ready": True}
        event = {"teams": [team]}
        commands = []
        reset = workshop["reset"]
        with patch.dict(reset.__globals__, {
            "check_host": lambda *_: None,
            "owned_resources": lambda *_: ({}, {}),
            "provision": lambda event, slots, **options: commands.append((slots, options)),
        }):
            reset(event, 1)
        self.assertEqual(commands, [([1], {"replacing": True})])
        self.assertEqual(team["password"], "unchanged")
        self.assertTrue(team["resetting"])
        self.assertFalse(team["ready"])
        self.assertRegex(team["screen_generation"], r"^[0-9a-f]{12}$")

    def test_reset_budgets_new_disk_space_only_for_missing_vms(self):
        reset = workshop["reset"]
        event = {"teams": [{}, {}], "resources": {"disk_gib": 10}}
        capacity = []
        with patch.dict(reset.__globals__, {
            "owned_resources": lambda *_: ({"ws-team-1": {"status": "Running"}}, {}),
            "check_host": lambda *args: capacity.append(args),
            "provision": lambda *args, **options: None,
        }):
            reset(event, None)
        self.assertEqual(capacity, [(1, 10)])

    def test_rebuild_updates_connection_without_recreating_account_or_id(self):
        grant = workshop["grant_access"]
        statements = []
        team = {"login": "demo-aaaaaaaa-team-1-aaaaaaaa", "portal_login": "1",
                "password": "unchanged", "screen_generation": "a" * 12}

        def db(statement):
            statements.append(statement)
            return "42"

        with patch.dict(grant.__globals__, {"db": db}):
            grant(1, team, "replacement-key", "replacement-host", retained=True)
        self.assertEqual(len(statements), 1)
        sql = statements[0]
        self.assertIn("UPDATE guacamole_connection SET connection_name", sql)
        self.assertIn(f"{team['login']}|ready|{'a' * 12}", sql)
        self.assertIn(f"{team['login']}-r{'a' * 12}.guac", sql)
        self.assertIn("replacement-host", sql)
        self.assertNotIn("guacamole_entity", sql)
        self.assertNotIn("INSERT INTO guacamole_connection (", sql)

    def test_other_teams_get_access_before_a_slow_team_fails(self):
        event = {"teams": [{"ready": False} for _ in range(4)]}
        others_ready = threading.Event()
        granted = set()

        def save(snapshot):
            if all(snapshot["teams"][slot - 1]["ready"] for slot in (1, 3, 4)):
                others_ready.set()

        def wait_for_ssh(slot, require_init=False):
            if slot == 2:
                if not others_ready.wait(timeout=3):
                    raise AssertionError("Other teams were blocked by Team 2")
                raise RuntimeError("Team 2 SSH readiness timed out.")
            return "host key"

        def keygen(*args):
            path = Path(args[-1])
            path.write_text("private test key")
            path.with_suffix(".pub").write_text("public test key")

        def grant_access(slot, *_):
            granted.add(slot)

        with TemporaryDirectory() as tmp:
            stubs = {
                "tempfile": SimpleNamespace(TemporaryDirectory=lambda **_: TemporaryDirectory(dir=tmp)),
                "save": save,
                "networks": dict,
                "create_bridge": lambda *_: None,
                "run": keygen,
                "create_guest": lambda *_: None,
                "wait_for_ssh": wait_for_ssh,
                "grant_access": grant_access,
            }
            with patch.dict(provision.__globals__, stubs):
                with self.assertRaisesRegex(RuntimeError, r"team\(s\) 2"):
                    provision(event, range(1, 5))
        self.assertEqual(granted, {1, 3, 4})
        self.assertFalse(event["teams"][1]["ready"])
        self.assertEqual(event["teams"][1]["error"], "Team 2 SSH readiness timed out.")


class DashboardHostTest(unittest.TestCase):
    def setUp(self):
        self.event = {
            "name": "demo", "run": "a" * 16, "template": "test-vm",
            "teams": [
                {"login": "demo-aaaaaaaa-team-1-aaaaaaaa", "ready": True, "password": "fixture-one"},
                {"login": "demo-aaaaaaaa-team-2-aaaaaaaa", "ready": True, "password": "fixture-two"},
            ],
        }

    def test_roster_survives_unavailable_portal(self):
        def unavailable():
            raise RuntimeError("Fixture portal outage.")

        with patch.dict(host.__globals__, {
            "event_state": lambda: deepcopy(self.event),
            "guest_statuses": lambda _: {"ws-team-1": "Running", "ws-team-2": "Stopped"},
            "cached_active_logins": lambda _: unavailable(),
        }):
            result = host({"op": "state"})
            self.assertEqual([team["status"] for team in result["event"]["teams"]], ["Running", "Stopped"])
            self.assertTrue(all(team["active"] is None for team in result["event"]["teams"]))
            self.assertTrue(all(not team["ready"] for team in result["event"]["teams"]))
            self.assertIn("Session status is unknown", result["warnings"][0])

    def test_slot_reuse_rejects_reads_for_the_previous_login(self):
        with patch.dict(host.__globals__, {"event_state": lambda: deepcopy(self.event)}):
            for op in ("screen", "credentials"):
                with self.subTest(op=op), self.assertRaisesRegex(ValueError, "That team changed"):
                    host({"op": op, "slot": 1, "username": "old-bbbbbbbb-team-1-bbbbbbbb"})

    def test_numeric_portal_login_does_not_replace_team_identity(self):
        team = self.event["teams"][0]
        team["portal_login"] = "1"
        with patch.dict(host.__globals__, {
            "event_state": lambda: deepcopy(self.event),
            "guest_statuses": lambda _: {"ws-team-1": "Running"},
            "active_logins": set,
        }):
            credentials = host({"op": "credentials", "slot": 1, "username": team["login"]})
            self.assertEqual(credentials["username"], "1")
            self.assertEqual(credentials["team"], team["login"])


class DashboardTailscaleTest(unittest.TestCase):
    def test_tailscale_identity_is_required_before_sign_in_and_assets(self):
        server = dashboard_server["Server"](
            ("127.0.0.1", 0), dashboard_server["Dashboard"](b"fixture-password"),
            tailscale_host="peter.example.ts.net", tailscale_login="owner@example.test",
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for identity, expected in ((None, 403), ("other@example.test", 403),
                                       ("owner@example.test", 200)):
                with self.subTest(identity=identity):
                    connection = HTTPConnection(*server.server_address, timeout=3)
                    try:
                        headers = {"Host": "peter.example.ts.net"}
                        if identity:
                            headers["Tailscale-User-Login"] = identity
                        connection.request("GET", "/app.js", headers=headers)
                        self.assertEqual(connection.getresponse().status, expected)
                    finally:
                        connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


class ScreenRecordingTest(unittest.TestCase):
    def test_reconnect_restarts_at_the_new_screen_instead_of_old_offset(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "team-a.guac").write_bytes(b"old recording")
            (directory / "team-b.guac").write_bytes(b"another team")
            first = read_recording(directory, "team-a")
            (directory / "team-a.guac.1").write_bytes(b"new")
            current = read_recording(directory, "team-a", first["token"], first["offset"])
            self.assertNotEqual(current["token"], first["token"])
            self.assertEqual(current["offset"], 3)
            self.assertEqual(b64decode(current["data"]), b"new")

    def test_rotation_can_reuse_the_base_filename(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            old = directory / "team-a.guac.2"
            old.write_bytes(b"old")
            os.utime(old, (1, 1))
            (directory / "team-a.guac").write_bytes(b"latest")
            self.assertEqual(b64decode(read_recording(directory, "team-a")["data"]), b"latest")

    def test_pruning_retains_a_locked_recording_until_its_writer_exits(self):
        prune = runpy.run_path(str(ROOT / "infra" / "prune-recordings.py"))["prune"]
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            prefix = "demo-aaaaaaaa-team-1-aaaaaaaa.guac"
            old, active, newest = (directory / f"{prefix}.{suffix}" for suffix in (1, 2, 3))
            for path, stamp in ((old, 1), (active, 2), (newest, 100)):
                path.write_bytes(b"fixture")
                os.utime(path, (stamp, stamp))
            with subprocess.Popen(
                [sys.executable, "-c",
                 "import fcntl, sys; "
                 "f = open(sys.argv[1], 'r+b'); fcntl.lockf(f, fcntl.LOCK_EX); "
                 "print('locked', flush=True); sys.stdin.read()", str(active)],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
            ) as writer:
                try:
                    self.assertEqual(writer.stdout.readline(), "locked\n")
                    prune(directory, newest.stat().st_mtime_ns)
                    self.assertFalse(old.exists())
                    self.assertTrue(active.exists())
                    self.assertTrue(newest.exists())
                finally:
                    writer.communicate(timeout=3)
            prune(directory, newest.stat().st_mtime_ns)
            self.assertFalse(active.exists())
            self.assertTrue(newest.exists())


class ReleasePreparationTest(unittest.TestCase):
    def test_prepare_merges_local_compose_and_effective_extension(self):
        helper = runpy.run_path(str(ROOT / "infra" / "prepare-release.py"))
        with TemporaryDirectory() as tmp:
            release, baseline, candidate = (Path(tmp) / part for part in ("release", "base", "candidate"))
            extension = helper["JAR"]
            for tree in (release, baseline, candidate):
                (tree / "infra").mkdir(parents=True)
                (tree / extension.parent).mkdir(parents=True)
                for asset in helper["EXTENSION"]:
                    (tree / extension.parent.parent / asset).write_text("header\n")
            common = "one\ntwo\nthree\nfour\nfive\nsix\n"
            for tree, image, port in ((release, "new", "8080"), (baseline, "old", "8080"),
                                      (candidate, "old", "9000")):
                (tree / "infra/compose.yaml").write_text(f"image: {image}\n{common}port: {port}\n")
            (candidate / "infra/site-vpn.conf").write_text("keep local settings\n")
            for tree in (baseline, candidate):
                (tree / "templates").mkdir()
                (tree / "templates/retired.json").write_text("{}\n")
            (candidate / "templates/private.json").write_text("{}\n")
            with ZipFile(candidate / extension, "w") as archive:
                archive.writestr("clipboard.js", "custom clipboard integration\n")
                archive.writestr("local.js", "extra local asset\n")
            (release / "portal-reset/reset.js").write_text("new reconnect logic\n")

            helper["prepare"](release, baseline, candidate)

            self.assertEqual((candidate / "infra/compose.yaml").read_text(),
                             f"image: new\n{common}port: 9000\n")
            self.assertEqual((candidate / "infra/site-vpn.conf").read_text(), "keep local settings\n")
            self.assertFalse((candidate / "templates/retired.json").exists())
            self.assertTrue((candidate / "templates/private.json").is_file())
            with ZipFile(candidate / extension) as archive:
                self.assertEqual(archive.read("clipboard.js"), b"custom clipboard integration\n")
                self.assertEqual(archive.read("reset.js"), b"new reconnect logic\n")
                self.assertEqual(archive.read("local.js"), b"extra local asset\n")
            self.assertEqual((candidate / ".release-base/infra/compose.yaml").read_text(),
                             f"image: new\n{common}port: 8080\n")

    def test_prepare_refuses_an_unresolved_local_change(self):
        prepare = runpy.run_path(str(ROOT / "infra" / "prepare-release.py"))["prepare"]
        with TemporaryDirectory() as tmp:
            release, baseline, candidate = (Path(tmp) / part for part in ("release", "base", "candidate"))
            for tree, value in ((release, "upstream"), (baseline, "base"), (candidate, "local")):
                tree.mkdir()
                (tree / "workshop").write_text(value + "\n")
            with self.assertRaisesRegex(SystemExit, "Reconcile local changes.*workshop"):
                prepare(release, baseline, candidate)
            self.assertEqual((candidate / "workshop").read_text(), "local\n")


class ActiveSessionTest(unittest.TestCase):
    def test_live_socket_is_required_for_open_history(self):
        active_logins = host.__globals__["active_logins"]
        web, guacd = "2026-11-16T09:00:00Z", "2026-11-16T09:30:00Z"
        login, stale = "demo-aaaaaaaa-team-1-aaaaaaaa", "demo-aaaaaaaa-team-2-bbbbbbbb"

        def run(*args, **options):
            if args[1] == "inspect":
                return f"true healthy {web} 123\ntrue healthy {guacd} 456"
            self.assertIn(f"GREATEST('{web}'::timestamptz, '{guacd}'::timestamptz)", args[-1])
            return f"{login}\n{stale}"

        with patch.dict(host.__globals__, {"run": run, "live_ssh_slots": lambda pid: {"1"} if pid == 456 else set()}):
            self.assertEqual(active_logins(), {login})


class TemplateTest(unittest.TestCase):
    def test_dashboard_catalog_lists_the_two_bundled_templates(self):
        images = [{"type": "virtual-machine", "aliases": [{"name": name}]}
                  for name in ("debian-trixie", "retep-lab")]
        catalog = host.__globals__["catalog"]
        with patch.dict(catalog.__globals__, {"INSTALL": ROOT, "run": lambda *a, **k: json.dumps(images)}):
            self.assertEqual([(item["id"], item["label"]) for item in catalog()],
                             [("base", "Base"), ("malware", "Malware")])

    def test_new_template_cli_creates_a_valid_starter_and_preserves_existing_files(self):
        with TemporaryDirectory() as tmp:
            checkout = Path(tmp)
            for relative in ("workshop", "workshop_templates.py", "templates/starter-init.sh",
                             "templates/base/workshop.json"):
                target = checkout / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                copyfile(ROOT / relative, target)

            def cli(*args):
                return subprocess.run([sys.executable, str(checkout / "workshop"), *args],
                                      capture_output=True, text=True, timeout=10)

            result = cli("new-template", "my-lab", "--description", "Lab for cafés")
            self.assertEqual(result.returncode, 0, result.stderr)
            catalog = checkout / "templates"
            template = load_template(catalog, "my-lab")
            self.assertEqual(template["description"], "Lab for cafés")
            self.assertEqual(template["image"], "debian-trixie")
            self.assertEqual(template["label"], "my-lab")
            self.assertEqual(template["init"], (catalog / "starter-init.sh").read_text())
            result = cli("validate-template", "my-lab")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("up to 4 team(s)", result.stdout)

            base = load_template(catalog, "base")
            for name in ("my-lab", "base", "../outside"):
                with self.subTest(name=name):
                    result = cli("new-template", name, "--description", "Replacement")
                    self.assertEqual(result.returncode, 1, result.stdout)
            self.assertEqual(load_template(catalog, "my-lab"), template)
            self.assertEqual(load_template(catalog, "base"), base)
            self.assertFalse((checkout / "outside").exists())

    def test_template_resources_and_script_are_applied_at_guest_creation(self):
        create = workshop["create_guest"]
        calls = []
        initializer = (ROOT / "templates/starter-init.sh").read_text()
        event = {"run": "a" * 16, "image": "b" * 64,
                 "resources": {"vcpus": 1, "memory_mib": 1024, "disk_gib": 12}, "init": initializer}
        with patch.dict(create.__globals__, {"incus": lambda *args: calls.append(args)}):
            create(1, event, "ssh-ed25519 test-key")
        self.assertIn("limits.cpu=1", calls[0])
        self.assertIn("limits.memory=1024MiB", calls[0])
        self.assertIn(("config", "device", "override", "ws-team-1", "root", "size=12GiB"), calls)
        encoded = next(arg for arg in calls[0] if arg.startswith("cloud-init.user-data="))
        config = json.loads(encoded.split("\n", 1)[1])
        script = next(file for file in config["write_files"] if file["path"].endswith("/init.sh"))
        self.assertEqual(script["content"], initializer)
        self.assertIn("bash -e /usr/local/lib/workshop/init.sh", config["runcmd"][-1][-1])

    def test_failed_initializer_prevents_portal_readiness(self):
        wait = workshop["wait_for_ssh"]
        with patch.dict(wait.__globals__, {"incus": lambda *a, **k: "workshop-init-failed"}):
            with self.assertRaisesRegex(RuntimeError, "init.sh failed"):
                wait(1, require_init=True)

    def test_manifest_validates_resource_types_and_bounds_teams(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            folder = directory / "lab"
            folder.mkdir()
            manifest = folder / "workshop.json"
            data = {"version": 1, "description": "Lab", "resources": {"vcpus": 3, "memory_mib": 2048}}
            manifest.write_text(json.dumps(data))
            self.assertEqual(team_limit(load_template(directory, "lab")["resources"]), 2)
            data["resources"]["vcpus"] = True
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "vcpus must be an integer"):
                load_template(directory, "lab")


if __name__ == "__main__":
    unittest.main()
