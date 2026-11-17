#!/usr/bin/env python3
"""Privileged local socket endpoint. The web process can request only workshop actions."""

import json
from pathlib import Path
import re
import subprocess
import sys

from mirror import read_recording

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from workshop_templates import DEFAULT_RESOURCES, SLUG, load_template, portal_url, team_limit, template_names

INSTALL = Path("/opt/workshop")
EVENT = Path("/var/lib/workshop/event.json")
LOGIN = re.compile(r"[a-z][a-z0-9-]{0,23}-[0-9a-f]{8}-team-([1-4])(?:-[0-9a-f]{8})?")


def run(*args, timeout=12):
    result = subprocess.run(args, text=True, capture_output=True, stdin=subprocess.DEVNULL,
                            timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:800] or "Peter could not complete the request.")
    return result.stdout.strip()


def catalog():
    templates = []
    images = json.loads(run("incus", "--force-local", "--project", "workshop",
                            "image", "list", "--format", "json", timeout=3))
    aliases = {alias["name"] for image in images if image["type"] == "virtual-machine"
               for alias in image["aliases"] or []}
    directory = INSTALL / "templates"
    for name in template_names(directory):
        try:
            template = load_template(directory, name)
        except (OSError, ValueError):
            continue
        if template["image"] in aliases:
            templates.append({"id": name, "description": template["description"],
                              "teamLimit": team_limit(template["resources"])})
    return templates


def event_state():
    try:
        return json.loads(EVENT.read_text())
    except FileNotFoundError:
        return None


def active_logins():
    containers = run("docker", "inspect", "--format",
                     "{{.State.Running}} {{.State.Health.Status}} {{.State.StartedAt}}",
                     "workshop-web-1", "workshop-guacd-1", timeout=3).splitlines()
    if len(containers) != 2 or not all(line.startswith("true healthy ") for line in containers):
        raise RuntimeError("The portal is unavailable.")
    start_times = [line.split()[-1] for line in containers]
    if not all(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", value)
               for value in start_times):
        raise RuntimeError("The portal is unavailable.")
    web, guacd = start_times
    sql = ("SELECT DISTINCT split_part(connection_name, '|', 1) FROM guacamole_connection_history "
           "WHERE connection_id IS NOT NULL AND end_date IS NULL "
           f"AND start_date >= GREATEST('{web}'::timestamptz, '{guacd}'::timestamptz);")
    history = run("docker", "exec", "--user", "postgres", "workshop-db-1", "psql",
                  "-XqAt", "--dbname", "guacamole", "-c", sql, timeout=3).splitlines()
    if not history:
        return set()
    # A killed guacd worker can leave an open PostgreSQL history row behind.
    # Corroborate it with a live outbound SSH socket in guacd's namespace.
    sockets = run("docker", "exec", "workshop-guacd-1", "netstat", "-tn", timeout=3)
    live_slots = set(re.findall(r"^tcp\s+\d+\s+\d+\s+\S+\s+10\.241\.([1-4])\.2:22\s+ESTABLISHED\s*$",
                                sockets, re.MULTILINE))
    return {login for login in history if (match := LOGIN.fullmatch(login)) and match[1] in live_slots}


def guest_statuses(event):
    vms = json.loads(run("incus", "--force-local", "--project", "workshop", "list",
                         "--format", "json", timeout=3))
    return {vm["name"]: vm["status"] for vm in vms
            if vm.get("config", {}).get("user.workshop.run") == event["run"]}


def state():
    event = event_state()
    result = {"portal": portal_url(), "templates": [], "event": None, "warnings": []}
    warnings = result["warnings"]
    if not event:
        try:
            result["templates"] = catalog()
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
            warnings.append("Peter could not load the VM templates. Retrying…")
        return result
    try:
        statuses = guest_statuses(event)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        statuses = None
        warnings.append("Peter could not check VM status. Retrying…")
    try:
        active = active_logins()
    except (OSError, RuntimeError, subprocess.TimeoutExpired):
        active = None
        warnings.append("The participant portal is unavailable. Session status is unknown.")
    teams = []
    for slot, team in enumerate(event["teams"], 1):
        if team is None:
            continue
        status = statuses.get(f"ws-team-{slot}", "Missing") if statuses is not None else "Unknown"
        ready = team["ready"] and status == "Running" and active is not None
        session = None if active is None or statuses is None else ready and team["login"] in active
        teams.append({"slot": slot, "status": status, "provisioned": team["ready"],
                      "ready": ready, "username": team["login"], "error": team.get("error"),
                      "active": session, "resetting": team.get("resetting", False),
                      "screenGeneration": team.get("screen_generation")})
    result["event"] = {"name": event["name"], "run": event["run"], "template": event["template"],
                       "teams": teams, "teamLimit": team_limit(event.get("resources", DEFAULT_RESOURCES))}
    return result


def team_at(slot, username):
    event = event_state()
    if type(slot) is not int or not event or not 1 <= slot <= len(event["teams"]):
        raise ValueError("That team does not exist.")
    team = event["teams"][slot - 1]
    if team is None or team["login"] != username:
        raise ValueError("That team changed. Refresh the dashboard and try again.")
    return event, team


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
    if op in {"credentials", "screen"}:
        slot, username = data.get("slot"), data.get("username")
        event, team = team_at(slot, username)
        if op == "screen":
            generation = team.get("screen_generation")
            recording = f"{username}-r{generation}" if generation else username
            path = Path(run("docker", "volume", "inspect", "--format", "{{.Mountpoint}}",
                            "workshop_screens", timeout=3))
            chunk = read_recording(path, recording, data.get("token"), data.get("offset", 0))
            _, current = team_at(slot, username)
            if current.get("screen_generation") != generation:
                raise ValueError("The team screen changed during the request.")
            return {**chunk, "team": username, "generation": generation}
        if not team["ready"] or guest_statuses(event).get(f"ws-team-{slot}") != "Running":
            raise ValueError("This team is not ready to connect.")
        active_logins()
        _, team = team_at(slot, username)
        if not team["ready"]:
            raise ValueError("This team is not ready to connect.")
        return {"team": username, "username": team.get("portal_login", username),
                "password": team["password"], "portal": portal_url()}
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
