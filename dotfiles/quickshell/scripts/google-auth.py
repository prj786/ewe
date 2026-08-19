#!/usr/bin/env python3
"""google-auth.py — ewe's Google OAuth helper (stdlib only).

The QML shell can't host a TCP loopback server, so this helper owns the
OAuth 2.0 installed-app flow (PKCE + loopback redirect — Google removed the
OOB copy-paste flow) and the keyring I/O. The shell invokes it via Process
and parses ONE JSON object from stdout; every failure path still prints
JSON and exits 0, so the shell never hangs or crashes on it.

Subcommands:
  status   -> {configured, signed_in, profile}
  login    -> browser consent -> refresh token into the keyring,
              profile cache to disk, prints {ok, profile, access_token, expires_at}
  refresh  -> access token from the stored refresh token
  logout   -> revoke at Google + clear keyring + profile cache

Secrets policy: the refresh token lives ONLY in the Secret Service keyring
(gnome-keyring; via `secret-tool`). The client id/secret live in the
gitignored ~/.config/quickshell/google-oauth.json — a Google "Desktop app"
OAuth client (its client_secret is explicitly not confidential). Nothing
secret is ever written under version control or plaintext state files:
google-profile.json only caches name/email/avatar-URL.
"""

import base64
import hashlib
import json
import os
import secrets as pysecrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

CONFIG = os.path.expanduser("~/.config/quickshell/google-oauth.json")
PROFILE_CACHE = os.path.expanduser("~/.config/quickshell/google-profile.json")

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
REVOKE_URL = "https://oauth2.googleapis.com/revoke"
USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
# gmail.readonly is a RESTRICTED scope: works for a personal client published
# "In production" (unverified-app warning clickthrough) — see README
SCOPES = "openid email profile https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/drive.appdata https://www.googleapis.com/auth/gmail.readonly"

KEYRING_ARGS = ["service", "ewe", "account", "google"]
# pre-rename installs stored the refresh token under this service name;
# keyring_get() migrates it forward once so nobody has to re-authenticate
OLD_KEYRING_ARGS = ["service", "hypr-shell", "account", "google"]
LOGIN_TIMEOUT = 300  # seconds to wait for the browser round-trip


def out(obj):
    print(json.dumps(obj))
    sys.exit(0)


def read_client():
    cid = os.environ.get("EWE_GOOGLE_CLIENT_ID", "") or os.environ.get("HYPRSHELL_GOOGLE_CLIENT_ID", "")
    csec = os.environ.get("EWE_GOOGLE_CLIENT_SECRET", "") or os.environ.get("HYPRSHELL_GOOGLE_CLIENT_SECRET", "")
    if not cid:
        try:
            with open(CONFIG) as f:
                j = json.load(f)
            # accept both the flat form ({client_id, client_secret}) and the
            # credentials JSON downloaded from the Google Cloud console, which
            # wraps a Desktop-app client in {"installed": {...}}
            if isinstance(j.get("installed"), dict):
                j = j["installed"]
            cid = j.get("client_id", "")
            csec = j.get("client_secret", csec)
        except (OSError, ValueError):
            pass
    return cid, csec


def keyring_get():
    try:
        r = subprocess.run(["secret-tool", "lookup", *KEYRING_ARGS],
                           capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
        # one-time migration from the pre-rename service name
        r = subprocess.run(["secret-tool", "lookup", *OLD_KEYRING_ARGS],
                           capture_output=True, text=True, timeout=10)
        tok = r.stdout.strip() if r.returncode == 0 else ""
        if tok and keyring_set(tok):
            subprocess.run(["secret-tool", "clear", *OLD_KEYRING_ARGS],
                           capture_output=True, text=True, timeout=10)
        return tok
    except (OSError, subprocess.TimeoutExpired):
        return ""


def keyring_set(token):
    r = subprocess.run(["secret-tool", "store", "--label=ewe Google", *KEYRING_ARGS],
                       input=token, capture_output=True, text=True, timeout=10)
    return r.returncode == 0


def keyring_clear():
    subprocess.run(["secret-tool", "clear", *KEYRING_ARGS],
                   capture_output=True, text=True, timeout=10)


def read_profile_cache():
    try:
        with open(PROFILE_CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_profile_cache(profile):
    tmp = PROFILE_CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(profile, f)
    os.replace(tmp, PROFILE_CACHE)


def http_post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode()), None
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode())
        except ValueError:
            body = {}
        return None, body.get("error", "http-%d" % e.code)
    except (urllib.error.URLError, OSError) as e:
        return None, "network: %s" % e


def fetch_userinfo(access_token):
    req = urllib.request.Request(USERINFO_URL, headers={"Authorization": "Bearer " + access_token})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            j = json.loads(resp.read().decode())
        return {"name": j.get("name", ""), "email": j.get("email", ""), "picture": j.get("picture", "")}
    except (urllib.error.URLError, OSError, ValueError):
        return {"name": "", "email": "", "picture": ""}


def cmd_status():
    cid, _ = read_client()
    keyring_ok = True
    try:
        subprocess.run(["secret-tool", "--help"], capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        keyring_ok = False
    out({"configured": bool(cid), "keyring": keyring_ok,
         "signed_in": bool(keyring_get()), "profile": read_profile_cache()})


def cmd_login():
    cid, csec = read_client()
    if not cid:
        out({"ok": False, "error": "not-configured"})
    if not keyring_set("ewe-keyring-probe"):
        out({"ok": False, "error": "keyring-unavailable"})
    keyring_clear()

    verifier = base64.urlsafe_b64encode(pysecrets.token_bytes(48)).decode().rstrip("=")
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    state = pysecrets.token_urlsafe(24)

    result = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            q = urllib.parse.urlparse(self.path)
            params = dict(urllib.parse.parse_qsl(q.query))
            body = "<html><body style='background:#1d1d1d;color:#eee;font-family:sans-serif'>" \
                   "<h2>ewe</h2><p>%s</p></body></html>"
            if q.path != "/callback":
                self.send_response(404); self.end_headers(); return
            if params.get("state") != state:
                result["error"] = "state-mismatch"
                msg = "Sign-in failed (state mismatch) — you can close this tab."
            elif "error" in params:
                result["error"] = params["error"]
                msg = "Sign-in was cancelled — you can close this tab."
            elif "code" in params:
                result["code"] = params["code"]
                msg = "Signed in — you can close this tab and return to the shell."
            else:
                result["error"] = "no-code"
                msg = "Sign-in failed — you can close this tab."
            data = (body % msg).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    srv = HTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_address[1]
    redirect = "http://127.0.0.1:%d/callback" % port

    auth = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": cid, "redirect_uri": redirect, "response_type": "code",
        "scope": SCOPES, "code_challenge": challenge, "code_challenge_method": "S256",
        "access_type": "offline", "prompt": "consent", "state": state,
    })
    subprocess.Popen(["xdg-open", auth], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    srv.timeout = 5
    deadline = time.time() + LOGIN_TIMEOUT
    while time.time() < deadline and not result:
        srv.handle_request()
    srv.server_close()

    if "code" not in result:
        out({"ok": False, "error": result.get("error", "timeout")})

    tok, err = http_post_form(TOKEN_URL, {
        "client_id": cid, "client_secret": csec, "code": result["code"],
        "code_verifier": verifier, "grant_type": "authorization_code",
        "redirect_uri": redirect,
    })
    if err or "access_token" not in (tok or {}):
        out({"ok": False, "error": "token-exchange: %s" % (err or "no access_token")})
    if "refresh_token" not in tok:
        out({"ok": False, "error": "no-refresh-token"})
    if not keyring_set(tok["refresh_token"]):
        out({"ok": False, "error": "keyring-store-failed"})

    profile = fetch_userinfo(tok["access_token"])
    write_profile_cache(profile)
    out({"ok": True, "profile": profile, "access_token": tok["access_token"],
         "expires_at": int(time.time()) + int(tok.get("expires_in", 3600))})


def cmd_refresh():
    cid, csec = read_client()
    if not cid:
        out({"ok": False, "error": "not-configured"})
    rt = keyring_get()
    if not rt:
        out({"ok": False, "error": "signed-out"})
    tok, err = http_post_form(TOKEN_URL, {
        "client_id": cid, "client_secret": csec,
        "refresh_token": rt, "grant_type": "refresh_token",
    })
    if err == "invalid_grant":
        # token was revoked server-side — drop the dead session cleanly
        keyring_clear()
        try:
            os.remove(PROFILE_CACHE)
        except OSError:
            pass
        out({"ok": False, "error": "signed-out", "reason": "invalid_grant"})
    if err or "access_token" not in (tok or {}):
        out({"ok": False, "error": err or "no access_token"})
    out({"ok": True, "access_token": tok["access_token"],
         "expires_at": int(time.time()) + int(tok.get("expires_in", 3600))})


def cmd_logout():
    rt = keyring_get()
    if rt:
        try:
            urllib.request.urlopen(
                urllib.request.Request(REVOKE_URL, data=urllib.parse.urlencode({"token": rt}).encode(),
                                       headers={"Content-Type": "application/x-www-form-urlencoded"}),
                timeout=15)
        except (urllib.error.URLError, OSError):
            pass  # offline logout still clears local state
    keyring_clear()
    try:
        os.remove(PROFILE_CACHE)
    except OSError:
        pass
    out({"ok": True})


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    try:
        {"status": cmd_status, "login": cmd_login,
         "refresh": cmd_refresh, "logout": cmd_logout}.get(cmd, cmd_status)()
    except SystemExit:
        raise
    except Exception as e:  # absolute backstop: still emit parseable JSON
        print(json.dumps({"ok": False, "error": "internal: %s" % e}))
