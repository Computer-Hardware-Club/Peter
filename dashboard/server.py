#!/usr/bin/env python3
"""Private workshop dashboard. Privileged actions run through a local Unix socket."""

import argparse
from collections import deque
from email.message import EmailMessage
from http import HTTPStatus
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import smtplib
import socket
import ssl
import threading
import time

ASSETS = Path(__file__).resolve().parent
SOCKET = "/run/workshop-dashboard-host.sock"
MAILBOX = re.compile(r"[A-Za-z0-9_+.-]+@oregonstate\.edu", re.IGNORECASE)
TEAM_PATH = re.compile(r"/api/team/([1-4])/(credentials|transcript)")
FILES = {"/": ("index.html", "text/html"), "/app.js": ("app.js", "text/javascript"),
         "/style.css": ("style.css", "text/css")}
SESSION_LIFETIME = 8 * 60 * 60
ACTIONS = {"deploy": "Start workshop", "add": "Add team", "remove": "Remove team",
           "reset": "Refresh VM", "destroy": "End workshop"}


def host_request(op, **data):
    message = (json.dumps({"op": op, **data}) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1210 if op == "action" else 16)
        client.connect(SOCKET)
        client.sendall(message)
        with client.makefile("rb") as stream:
            result = json.loads(stream.readline(524288))
    if result.get("error"):
        raise ValueError(result["error"])
    return result


def send_invite(mail, email, team):
    message = EmailMessage()
    message["From"] = mail["sender"]
    message["To"] = email
    message["Subject"] = "Your Computer Hardware Club workshop login"
    message.set_content(
        f"Open {team['portal']} and sign in with a code sent to your OSU email.\n\n"
        f"Team username: {team['username']}\n"
        f"Team password: {team['password']}\n\n"
        "One teammate can use the terminal at a time. Workshop officers can view "
        "terminal output to help troubleshoot.\n"
    )
    tls = ssl.create_default_context()
    mode = mail.get("security", "starttls")
    if mode == "tls":
        client = smtplib.SMTP_SSL(mail["host"], mail.get("port", 465), context=tls, timeout=10)
    elif mode == "starttls":
        client = smtplib.SMTP(mail["host"], mail.get("port", 587), timeout=10)
    else:
        raise ValueError("SMTP must use TLS or STARTTLS.")
    with client:
        if mode == "starttls":
            client.starttls(context=tls)
        if mail.get("username"):
            client.login(mail["username"], mail["password"])
        client.send_message(message)


class Dashboard:
    def __init__(self, password, mail):
        self.password = password
        self.mail = mail
        self.lock = threading.Lock()
        self.sessions = {}
        self.failures = deque(maxlen=24)
        self.job = None
        self.invitations = deque(maxlen=24)

    def login(self, password):
        with self.lock:
            now = time.monotonic()
            while self.failures and self.failures[0] < now - 60:
                self.failures.popleft()
            if len(self.failures) >= 24:
                raise PermissionError("Too many sign-in attempts. Wait one minute.")
            if not isinstance(password, str) or not secrets.compare_digest(
                    password.encode(), self.password):
                self.failures.append(now)
                return None
            self.sessions = {key: value for key, value in self.sessions.items() if value[1] > now}
            if len(self.sessions) >= 64:
                del self.sessions[next(iter(self.sessions))]
            key, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
            self.sessions[key] = (csrf, now + SESSION_LIFETIME)
            return key, csrf

    def session(self, key):
        with self.lock:
            stored = self.sessions.get(key)
            if stored and stored[1] > time.monotonic():
                return stored[0]
            self.sessions.pop(key, None)
            return None

    def logout(self, key):
        with self.lock:
            self.sessions.pop(key, None)

    def start_action(self, data):
        label = ACTIONS.get(data.get("action")) if isinstance(data.get("action"), str) else None
        if not label:
            raise ValueError("Unknown workshop action.")
        with self.lock:
            if self.job and self.job["state"] == "running":
                return False
            self.job = {"label": label, "state": "running"}
        threading.Thread(target=self.run_action, args=(data,), daemon=True).start()
        return True

    def run_action(self, data):
        job = {"label": ACTIONS[data["action"]], "state": "done"}
        try:
            host_request("action", **{key: value for key, value in data.items()
                                      if key in {"action", "name", "template", "teams", "slot",
                                                 "run", "username"}})
        except ValueError as exc:
            job.update(state="failed", error=str(exc))
        except (OSError, EOFError):
            job.update(state="failed", error="Peter did not report the result. Check the VM status.")
        with self.lock:
            self.job = job

    def state(self, csrf):
        with self.lock:
            job = self.job
        result = host_request("state")
        return {**result, "csrf": csrf, "job": job, "mailConfigured": bool(self.mail)}

    def invite(self, data):
        email = data.get("email")
        if not isinstance(email, str) or len(email) > 254 or not MAILBOX.fullmatch(email):
            raise ValueError("Enter a valid @oregonstate.edu email address.")
        if not self.mail:
            raise ValueError("SMTP is not configured. Open a draft in your email app.")
        with self.lock:
            now = time.monotonic()
            while self.invitations and self.invitations[0] < now - 60:
                self.invitations.popleft()
            if len(self.invitations) >= 24:
                raise PermissionError("Invite limit reached. Wait one minute.")
            self.invitations.append(now)
        team = host_request("credentials", slot=data.get("slot"))
        if data.get("username") != team["username"]:
            raise ValueError("That team changed. Open its new invitation before sending.")
        try:
            send_invite(self.mail, email, team)
        except (OSError, smtplib.SMTPException, KeyError):
            raise ValueError("The mail server did not accept the invitation. Check SMTP settings.") from None


class Request(BaseHTTPRequestHandler):
    server_version = "WorkshopDashboard"

    def log_message(self, *args):
        pass  # Requests can contain administrative data.

    def respond(self, status, value, content_type="application/json", cookie=None):
        body = json.dumps(value).encode() if content_type == "application/json" else value
        self.send_response(status)
        self.send_header("Content-Type", content_type + "; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'; form-action 'self'")
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, message):
        self.respond(status, {"error": message})

    def cookie(self, value, age):
        flags = "; Secure" if self.server.tls else ""
        return f"workshop_session={value}; Path=/; Max-Age={age}; HttpOnly; SameSite=Strict{flags}"

    def session_key(self):
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get("Cookie", ""))
        except CookieError:
            return ""
        return cookie["workshop_session"].value if "workshop_session" in cookie else ""

    def correct_host(self):
        if self.headers.get("Host") == self.server.host_header:
            return True
        self.error(HTTPStatus.MISDIRECTED_REQUEST, "Open the dashboard using its configured address.")
        return False

    def read_json(self):
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 8192 or self.headers.get_content_type() != "application/json":
            raise ValueError("Expected a small JSON request.")
        data = json.loads(self.rfile.read(size))
        if not isinstance(data, dict):
            raise ValueError("Invalid dashboard request.")
        return data

    def do_GET(self):
        if not self.correct_host():
            return
        if self.path in FILES:
            name, media = FILES[self.path]
            self.respond(HTTPStatus.OK, (ASSETS / name).read_bytes(), media)
            return
        app = self.server.dashboard
        csrf = app.session(self.session_key())
        if not csrf:
            self.error(HTTPStatus.UNAUTHORIZED, "Sign in to the officer dashboard.")
            return
        try:
            if self.path == "/api/state":
                self.respond(HTTPStatus.OK, app.state(csrf))
            elif match := TEAM_PATH.fullmatch(self.path):
                self.respond(HTTPStatus.OK, host_request(match[2], slot=int(match[1])))
            else:
                self.error(HTTPStatus.NOT_FOUND, "Page not found.")
        except ValueError as exc:
            self.error(HTTPStatus.BAD_REQUEST, str(exc))
        except (OSError, EOFError):
            self.error(HTTPStatus.SERVICE_UNAVAILABLE, "The workshop service on Peter is unavailable.")

    def do_POST(self):
        if not self.correct_host():
            return
        if self.headers.get("Origin") != self.server.origin:
            self.error(HTTPStatus.FORBIDDEN, "Open the dashboard directly in your browser.")
            return
        app = self.server.dashboard
        try:
            data = self.read_json()
            if self.path == "/api/login":
                result = app.login(data.get("password"))
                if result:
                    key, csrf = result
                    self.respond(HTTPStatus.OK, {"csrf": csrf}, cookie=self.cookie(key, SESSION_LIFETIME))
                else:
                    self.error(HTTPStatus.UNAUTHORIZED, "Incorrect officer password.")
                return
            key = self.session_key()
            csrf = app.session(key)
            if not csrf:
                self.error(HTTPStatus.UNAUTHORIZED, "Sign in to the officer dashboard.")
                return
            supplied = self.headers.get("X-CSRF-Token", "").encode()
            if not secrets.compare_digest(csrf.encode(), supplied):
                self.error(HTTPStatus.FORBIDDEN, "Reload the dashboard and try again.")
                return
            if self.path == "/api/action":
                if app.start_action(data):
                    self.respond(HTTPStatus.ACCEPTED, {})
                else:
                    self.error(HTTPStatus.CONFLICT, "Another workshop action is in progress.")
            elif self.path == "/api/invite":
                app.invite(data)
                self.respond(HTTPStatus.OK, {})
            elif self.path == "/api/logout":
                app.logout(key)
                self.respond(HTTPStatus.OK, {}, cookie=self.cookie("", 0))
            else:
                self.error(HTTPStatus.NOT_FOUND, "Page not found.")
        except PermissionError as exc:
            self.error(HTTPStatus.TOO_MANY_REQUESTS, str(exc))
        except ValueError as exc:
            self.error(HTTPStatus.BAD_REQUEST, str(exc))
        except (OSError, EOFError):
            self.error(HTTPStatus.SERVICE_UNAVAILABLE, "The workshop service on Peter is unavailable.")


class Server(ThreadingHTTPServer):
    request_queue_size = 32

    def __init__(self, address, dashboard, tls=None, subnet=None):
        self.dashboard = dashboard
        self.tls = tls
        self.subnet = subnet
        self.slots = threading.BoundedSemaphore(32)
        self.host_header = f"{address[0]}:{address[1]}"
        self.origin = ("https://" if tls else "http://") + self.host_header
        super().__init__(address, Request)

    def verify_request(self, request, client_address):
        return self.subnet is None or ipaddress.IPv4Address(client_address[0]) in self.subnet

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        request.settimeout(8)
        try:
            if self.tls:
                request = self.tls.wrap_socket(request, server_side=True)
            super().process_request_thread(request, client_address)
        except (OSError, ssl.SSLError):
            self.shutdown_request(request)
        finally:
            self.slots.release()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lan")
    args = parser.parse_args()
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    password = (credentials / "officer-password").read_bytes().strip()
    if len(password) < 16:
        raise ValueError("The officer password must contain at least 16 characters.")
    mail = json.loads((credentials / "smtp.json").read_text())
    if not isinstance(mail, dict):
        raise ValueError("SMTP configuration must be a JSON object.")
    app = Dashboard(password, mail)
    local = Server(("127.0.0.1", 8090), app)
    if args.lan:
        address = ipaddress.IPv4Interface(args.lan)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_2
        tls.load_cert_chain(credentials / "tls.crt", credentials / "tls.key")
        lan = Server((str(address.ip), 8443), app, tls, address.network)
        threading.Thread(target=lan.serve_forever, daemon=True).start()
    local.serve_forever()


if __name__ == "__main__":
    main()
