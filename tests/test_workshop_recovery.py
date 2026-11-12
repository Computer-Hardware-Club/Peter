from base64 import b64decode
from copy import deepcopy
from http.client import HTTPConnection
import json
from pathlib import Path
import runpy
import sys
from tempfile import TemporaryDirectory
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch
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
            "provision": lambda event, slots, **options: commands.append((slots, options)),
        }):
            reset(event, 1)
        self.assertEqual(commands, [([1], {"replacing": True})])
        self.assertEqual(team["password"], "unchanged")
        self.assertTrue(team["resetting"])
        self.assertFalse(team["ready"])
        self.assertRegex(team["screen_generation"], r"^[0-9a-f]{12}$")

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
            "active_logins": unavailable,
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


class TemplateTest(unittest.TestCase):
    def test_example_resources_and_script_are_applied_at_guest_creation(self):
        template = load_template(ROOT / "templates", "hello-lab")
        create = workshop["create_guest"]
        calls = []
        event = {"run": "a" * 16, "image": "b" * 64, "resources": template["resources"],
                 "init": template["init"]}
        with patch.dict(create.__globals__, {"incus": lambda *args: calls.append(args)}):
            create(1, event, "ssh-ed25519 test-key")
        self.assertIn("limits.cpu=1", calls[0])
        self.assertIn("limits.memory=1024MiB", calls[0])
        self.assertIn(("config", "device", "override", "ws-team-1", "root", "size=12GiB"), calls)
        encoded = next(arg for arg in calls[0] if arg.startswith("cloud-init.user-data="))
        config = json.loads(encoded.split("\n", 1)[1])
        script = next(file for file in config["write_files"] if file["path"].endswith("/init.sh"))
        self.assertEqual(script["content"], template["init"])
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
