#!/usr/bin/env python3
"""Privileged local socket endpoint. The web process can request only workshop actions."""

import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

INSTALL = Path("/opt/workshop")
EVENT = Path("/var/lib/workshop/event.json")
PORTAL = "https://workshop.computerhardwareclub.org/"
SLUG = re.compile(r"[a-z][a-z0-9-]{0,23}")
LOGIN = re.compile(r"[a-z][a-z0-9-]{0,23}-[0-9a-f]{8}-team-[1-4](?:-[0-9a-f]{8})?")
# Remove terminal control strings, ANSI sequences, and control characters other than whitespace.
ANSI = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[@-_]")
CONTROL = re.compile(r"[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f-\x9f]")


def run(*args, timeout=12):
    result = subprocess.run(args, text=True, capture_output=True, stdin=subprocess.DEVNULL,
                            timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:800] or "Peter could not complete the request.")
    return result.stdout.strip()


def catalog():
    templates = []
    images = json.loads(run("incus", "--force-local", "--project", "workshop",
                            "image", "list", "--format", "json"))
    aliases = {alias["name"] for image in images if image["type"] == "virtual-machine"
               for alias in image["aliases"] or []}
    for path in sorted((INSTALL / "templates").glob("*.json")):
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if (isinstance(data, dict) and SLUG.fullmatch(path.stem)
                and isinstance(data.get("image"), str) and data["image"] in aliases):
            templates.append({"id": path.stem, "description": data.get("description", "")})
    return templates


def event_state():
    try:
        return json.loads(EVENT.read_text())
    except FileNotFoundError:
        return None


def active_logins():
    started = run("docker", "inspect", "--format", "{{.State.StartedAt}}", "workshop-web-1")
    if not re.fullmatch(r"[0-9T:Z.+-]+", started):
        raise RuntimeError("Could not determine the portal start time.")
    sql = ("SELECT DISTINCT username FROM guacamole_connection_history "
           f"WHERE end_date IS NULL AND start_date >= '{started}'::timestamptz;")
    return set(run("docker", "exec", "--user", "postgres", "workshop-db-1", "psql",
                   "-XqAt", "--dbname", "guacamole", "-c", sql).splitlines())


def state():
    event = event_state()
    result = {"portal": PORTAL, "templates": catalog(), "event": None}
    if not event:
        return result
    vms = json.loads(run("incus", "--force-local", "--project", "workshop", "list",
                         "--format", "json"))
    statuses = {vm["name"]: vm["status"] for vm in vms
                if vm.get("config", {}).get("user.workshop.run") == event["run"]}
    active = active_logins()
    result["event"] = {"name": event["name"], "run": event["run"], "template": event["template"], "teams": [
        {"slot": slot, "status": statuses.get(f"ws-team-{slot}", "Missing"),
         "ready": team["ready"], "username": team["login"],
         "active": team["ready"] and statuses.get(f"ws-team-{slot}") == "Running"
         and team["login"] in active}
        for slot, team in enumerate(event["teams"], 1) if team is not None
    ]}
    return result


def team_at(slot):
    event = event_state()
    if type(slot) is not int or not event or not 1 <= slot <= len(event["teams"]):
        raise ValueError("That team does not exist.")
    team = event["teams"][slot - 1]
    if team is None:
        raise ValueError("That team does not exist.")
    return team


def transcript(team):
    login = team["login"]
    if not LOGIN.fullmatch(login):
        raise RuntimeError("Invalid team login in workshop state.")
    path = Path(run("docker", "volume", "inspect", "--format", "{{.Mountpoint}}",
                    "workshop_recordings"))
    storage = os.statvfs(path)
    nearly_full = storage.f_bavail * storage.f_frsize < 1024 * 1024
    pattern = re.compile(re.escape(login) + r"(?:\.([1-9][0-9]*))?")
    recordings = [(int(match[1] or 0), file) for file in path.iterdir()
                  if (match := pattern.fullmatch(file.name))]
    if not recordings:
        return {"text": "", "storageLow": nearly_full}
    file = max(recordings)[1]
    try:
        fd = os.open(file, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return {"text": "", "storageLow": nearly_full}
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise RuntimeError("Invalid recording file.")
        end = handle.seek(0, os.SEEK_END)
        handle.seek(max(0, end - 65536))
        output = handle.read(65536).decode("utf-8", "replace")
    return {"text": CONTROL.sub("", ANSI.sub("", output)).replace("\r\n", "\n").replace("\r", ""),
            "storageLow": nearly_full}


def action(data):
    name = data["action"]
    if name == "deploy":
        event, template, teams = data.get("name"), data.get("template"), data.get("teams")
        if not isinstance(event, str) or not SLUG.fullmatch(event):
            raise ValueError("Use a lowercase workshop name with up to 24 letters, numbers or hyphens.")
        if not isinstance(template, str) or not SLUG.fullmatch(template):
            raise ValueError("Choose a workshop template.")
        if type(teams) is not int or not 1 <= teams <= 4:
            raise ValueError("Choose between one and four teams.")
        args = ("deploy", event, "--template", template, "--teams", str(teams))
    elif name in {"add", "destroy"}:
        expected_run = data.get("run")
        if not isinstance(expected_run, str) or not re.fullmatch(r"[0-9a-f]{16}", expected_run):
            raise ValueError("Refresh the dashboard and choose the workshop again.")
        args = (name, "--expect-run", expected_run)
        if name == "destroy":
            args += ("--yes",)
    elif name in {"reset", "remove"}:
        slot = data.get("slot")
        if type(slot) is not int or not 1 <= slot <= 4:
            raise ValueError("Invalid team number.")
        username = data.get("username")
        if not isinstance(username, str) or not LOGIN.fullmatch(username):
            raise ValueError("Refresh the dashboard and choose the team again.")
        args = (name, "--team", str(slot), "--yes", "--expect-login", username)
        if name == "reset":
            args += ("--keep-password",)
    else:
        raise ValueError("Unknown workshop action.")
    run(str(INSTALL / "workshop"), *args, timeout=1200)
    return {}


def handle(data):
    op = data.get("op")
    if op == "state":
        return state()
    if op == "action":
        return action(data)
    if op in {"credentials", "transcript"}:
        team = team_at(data.get("slot"))
        if op == "transcript":
            return transcript(team)
        if not team["ready"]:
            raise ValueError("This team is still being prepared.")
        return {"username": team["login"], "password": team["password"], "portal": PORTAL}
    raise ValueError("Unknown dashboard operation.")


if __name__ == "__main__":
    try:
        line = sys.stdin.buffer.readline(4097)
        if len(line) > 4096:
            raise ValueError("Dashboard request is too large.")
        request = json.loads(line)
        if not isinstance(request, dict):
            raise ValueError("Invalid dashboard request.")
        result = handle(request)
    except (ValueError, RuntimeError) as exc:
        result = {"error": str(exc)}
    except (OSError, subprocess.TimeoutExpired, KeyError):
        result = {"error": "Peter could not complete the request. Check the dashboard service log."}
    print(json.dumps(result, ensure_ascii=True), flush=True)
