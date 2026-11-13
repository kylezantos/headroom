#!/usr/bin/env python3
"""Stub OpenCode Console for Headroom QA (KTD18, plan U12).

Serves only the routes the official OpenCode 2.x client calls while it reads
Go usage, signs in with the device-code flow and refreshes an OAuth token.
Every credential, workspace and account it hands out is fake.

USAGE (agents: read this)
  python3 -I Scripts/opencode-stub-console.py --port 48765 --mode go [--limited monthly]

  The stub runs in the FOREGROUND and binds 127.0.0.1 only. Never detach it
  (no nohup, no trailing '&' that outlives your command, no launchd). If you
  need it in the background while a client runs, start and stop it inside ONE
  shell command so it cannot outlive that command:

    python3 -I Scripts/opencode-stub-console.py --port 48765 --mode go & SP=$!
    trap 'kill $SP 2>/dev/null; wait $SP 2>/dev/null' EXIT
    ...run the client...

  Afterwards confirm nothing is left:
    ps -axo pid,ppid,command | grep opencode-stub-console | grep -v grep

Point a scratch home at it by importing a credential whose metadata.server is
http://127.0.0.1:<port>/console (Scripts/opencode-qa-home.sh does this).

MODES
  go          three Go windows (rolling, weekly, monthly), one budget
  nogo        403 on the Go route (no Go subscription)
  expired     401 on the Go route
  err500      500 on the Go route
  malformed   truncated JSON on the Go route
  wrongshape  valid JSON, wrong field types on the Go route
  slow        Go route answers after --slow-seconds (default 25; client times out at 15)
  revoked     401 on the Go, budgets AND config routes
  device      device-code sign-in (one 'authorization_pending', then a token
              naming workspace wrk_stub_device); usage then reads as go
  device-noworkspace
              device-code sign-in whose token carries no org_id and whose
              account has no workspaces (credential stores no orgID)
  refreshok   refresh_token grant succeeds with rotated fake tokens
  refreshbad  refresh_token grant fails with 400 invalid_grant

  --token-lifetime sets expires_in for device and refresh tokens (default 3600);
  a small value lets a seeded home age past expiry so the refresh path runs.
  --refresh-delay holds each refresh_token grant for that many seconds.

  --limited takes a comma list of rolling,weekly,monthly. Each named window
  reports status "rate-limited" at 100 percent.
"""

import argparse
import datetime
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODES = (
    "go", "nogo", "expired", "err500", "malformed", "wrongshape", "slow",
    "revoked", "device", "device-noworkspace", "refreshok", "refreshbad",
)
WINDOWS = ("rolling", "weekly", "monthly")

# Fixed offsets so each window has a distinct, plausible percentage and reset.
WINDOW_POSE = {
    "rolling": (29, datetime.timedelta(hours=3, minutes=12)),
    "weekly": (47, datetime.timedelta(days=3, hours=6)),
    "monthly": (63, datetime.timedelta(days=17, hours=9)),
}

STUB_WORKSPACE = {"id": "wrk_stub_device", "name": "Stub Device Workspace"}


def iso(delta):
    moment = datetime.datetime.now(datetime.timezone.utc) + delta
    return moment.isoformat(timespec="milliseconds").replace("+00:00", "Z")


class Handler(BaseHTTPRequestHandler):
    server_version = "opencode-stub-console"
    sys_version = ""
    mode = "go"
    limited = frozenset()
    slow_seconds = 25.0
    token_lifetime = 3600
    refresh_delay = 0.0
    log_file = None
    device_polls = 0
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def note(self, extra=""):
        line = "{} {} {} org={}{}".format(
            time.strftime("%H:%M:%S"), self.command, self.path,
            self.headers.get("x-opencode-org-id"), extra,
        )
        if self.log_file:
            with Handler.lock, open(self.log_file, "a") as handle:
                handle.write(line + "\n")

    def body(self):
        length = int(self.headers.get("content-length") or 0)
        return self.rfile.read(length).decode("utf-8", "replace") if length else ""

    def raw(self, code, data, content_type="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send(self, code, obj):
        self.raw(code, json.dumps(obj).encode())

    def go_usage(self):
        usage = {}
        for name in WINDOWS:
            percent, delta = WINDOW_POSE[name]
            limited = name in self.limited
            usage[name] = {
                "status": "rate-limited" if limited else "ok",
                "percent": 100 if limited else percent,
                "resetsAt": iso(delta),
            }
        return {"usage": usage}

    def budgets(self):
        return [{
            "ruleID": "rule_stub_monthly",
            "limitDollars": 50,
            "spentDollars": 12.5,
            "scope": "each",
            "per": "set",
            "coverage": "all",
            "models": [],
            "vendors": [],
            "picked": False,
            "shared": False,
            "resetsAt": iso(WINDOW_POSE["monthly"][1]),
        }]

    def handle_request(self):
        path = self.path.split("?", 1)[0]
        mode = self.mode
        payload = self.body() if self.command == "POST" else ""
        self.note()

        if path == "/console/auth/device/code":
            return self.send(200, {
                "device_code": "stub-device-code",
                "user_code": "STUB-CODE",
                "verification_uri_complete": "/auth/device?code=STUB-CODE",
                "expires_in": 600,
                "interval": 1,
            })
        if path == "/console/auth/device/token":
            if "refresh_token" in payload:
                if self.refresh_delay:
                    time.sleep(self.refresh_delay)
                if mode == "refreshbad":
                    return self.send(400, {"error": "invalid_grant"})
                return self.send(200, {
                    "access_token": "stub-rotated-access-token",
                    "refresh_token": "stub-rotated-refresh-token",
                    "expires_in": self.token_lifetime,
                    "org_id": "wrk_stub_device",
                })
            if mode not in ("device", "device-noworkspace"):
                return self.send(400, {"error": "access_denied"})
            with Handler.lock:
                Handler.device_polls += 1
                polls = Handler.device_polls
            if polls < 2:
                return self.send(400, {"error": "authorization_pending"})
            token = {
                "access_token": "stub-device-access-token",
                "refresh_token": "stub-device-refresh-token",
                "expires_in": self.token_lifetime,
            }
            if mode == "device":
                token["org_id"] = STUB_WORKSPACE["id"]
            return self.send(200, token)
        if path == "/console/api/user":
            return self.send(200, {"id": "usr_stub", "email": "stub-user@example.invalid"})
        if path == "/console/api/orgs":
            return self.send(200, [] if mode == "device-noworkspace" else [STUB_WORKSPACE])
        if path == "/console/api/v2/config":
            if mode == "revoked":
                return self.send(401, {"_tag": "Unauthorized"})
            return self.send(404, {"error": "not stubbed"})
        if path == "/console/api/policies/current-budgets":
            if mode == "revoked":
                return self.send(401, {"_tag": "Unauthorized"})
            return self.send(200, self.budgets())
        if path == "/zen/go/v1/usage":
            if mode == "nogo":
                return self.send(403, {"type": "error", "error": {
                    "type": "EntitlementError", "message": "OpenCode Go subscription required."}})
            if mode in ("expired", "revoked"):
                return self.send(401, {"error": {
                    "type": "authentication_error", "code": "invalid_api_key", "message": "expired"}})
            if mode == "err500":
                return self.send(500, {"error": "stub internal error"})
            if mode == "malformed":
                return self.raw(200, b'{"usage": {"rolling": "nope"')
            if mode == "wrongshape":
                return self.send(200, {"usage": {"rolling": {"percent": "abc"}}})
            if mode == "slow":
                time.sleep(self.slow_seconds)
            return self.send(200, self.go_usage())
        return self.send(404, {"error": "not stubbed"})

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()


def main():
    parser = argparse.ArgumentParser(
        description="Stub OpenCode Console (fake data, 127.0.0.1 only, foreground).",
        epilog="Run it in the foreground, or background it only inside one shell command "
               "that kills it on EXIT (see the module docstring).",
    )
    parser.add_argument("--port", type=int, default=48765)
    parser.add_argument("--mode", choices=MODES, default="go")
    parser.add_argument("--limited", default="", help="comma list of rolling,weekly,monthly")
    parser.add_argument("--slow-seconds", type=float, default=25.0)
    parser.add_argument("--token-lifetime", type=int, default=3600,
                        help="expires_in (seconds) for device and refresh tokens; small values age a home")
    parser.add_argument("--refresh-delay", type=float, default=0.0,
                        help="seconds to hold a refresh_token grant before answering (refresh-lock checks)")
    parser.add_argument("--log", help="append one line per request to this file")
    args = parser.parse_args()

    limited = frozenset(part for part in args.limited.split(",") if part)
    unknown = limited - set(WINDOWS)
    if unknown:
        parser.error("unknown window(s) for --limited: " + ",".join(sorted(unknown)))

    Handler.mode = args.mode
    Handler.limited = limited
    Handler.slow_seconds = args.slow_seconds
    Handler.token_lifetime = args.token_lifetime
    Handler.refresh_delay = args.refresh_delay
    Handler.log_file = args.log

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    print("opencode-stub-console mode={} limited={} on http://127.0.0.1:{}/console "
          "(foreground; stop it in the same command)".format(
              args.mode, ",".join(sorted(limited)) or "-", server.server_address[1]),
          file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
