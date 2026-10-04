#!/usr/bin/env bash
# ewe.mail tests — no compositor, no account. The logic is QML against the
# core CLIs, so what is testable here is the contract: the manifest (API 3,
# the legacy page key and IPC alias), both IPC targets with the same four
# verbs, the `status` reply's field set (ewe-settings reads it), that no
# token or password can ever reach a state file, and Rule 8.
set -euo pipefail
cd "$(dirname "$0")"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

# 1. manifest ────────────────────────────────────────────────────────────────
python3 - <<'PY' > "$SB/manifest.chk" 2>&1 || true
import json, re, os
m = json.load(open("manifest.json"))
assert m["id"] == "ewe.mail" and m["apiVersion"] == 3 and m["schemaVersion"] == 1
assert set(m["kinds"]) == {"service", "quick-page", "bar-status"}
assert m["quickPage"]["key"] == "mail", "legacy key `mail` keeps `quicksettings tab mail` working"
assert m["ipcAliases"] == ["mail"], "the shell's `mail` IPC target survives as an alias"
for k, f in m["entryPoints"].items(): assert os.path.isfile(f), f
assert re.match(r"^ic[A-Z]", m["icon"]) and re.match(r"^ic[A-Z]", m["quickPage"]["icon"])
print("MANIFEST-OK")
PY
check "manifest: id, API 3, kinds, legacy key, alias, icons" "grep -q MANIFEST-OK '$SB/manifest.chk'" || cat "$SB/manifest.chk"
check "qmldir declares the Inbox singleton" "grep -q '^singleton Inbox 1.0 Inbox.qml' qmldir"

# 2. IPC: both targets, the same four verbs ───────────────────────────────────
python3 - <<'PY' > "$SB/ipc.chk" 2>&1 || true
import re
s = open("Service.qml").read()
blocks = re.findall(r'IpcHandler\s*\{(.*?)\n    \}', s, re.S)
targets = {re.search(r'target:\s*"([^"]+)"', b).group(1): set(re.findall(r'function (\w+)\(', b)) for b in blocks}
assert set(targets) == {"ewe.mail", "mail"}, targets
for t, verbs in targets.items():
    assert verbs == {"refresh", "fetch", "setNotify", "status"}, (t, verbs)
assert 'function setNotify(on: bool): void' in s and 'function status(): string' in s
print("IPC-OK")
PY
check "IpcHandler ewe.mail + mail: refresh fetch setNotify status" "grep -q IPC-OK '$SB/ipc.chk'" || cat "$SB/ipc.chk"

# 3. the status reply — the field set the shell's Mail.qml returned, in order ─
python3 - <<'PY' > "$SB/status.chk" 2>&1 || true
import re
s = open("Inbox.qml").read()
body = re.search(r'function statusJson\(\)\s*\{\s*return JSON\.stringify\(\{(.*?)\}\)', s, re.S).group(1)
keys = re.findall(r'(\w+):\s*ml\.', body)
assert keys == ["probed", "source", "available", "title", "imapConfigured", "imapHost", "imapUser", "imapKeyring",
                "unread", "state", "error", "notify", "needsReconnect"], keys
print("STATUS-OK")
PY
check "status JSON has the shell's 13 fields in the shell's order" "grep -q STATUS-OK '$SB/status.chk'" || cat "$SB/status.chk"

# 4. Rule 2: no secret ever persisted ─────────────────────────────────────────
python3 - <<'PY' > "$SB/secret.chk" 2>&1 || true
import re
s = open("Inbox.qml").read()
writes = re.findall(r'_atomicWrite\([^,]+,\s*ml\.(\w+),\s*JSON\.stringify\(\{(.*?)\}\)\)', s, re.S)
assert len(writes) == 2, writes
for path, fields in writes:
    assert not re.search(r'token|password|secret', fields, re.I), (path, fields)
assert "_accessToken" in s and "access_token" in s        # the token exists in memory…
assert not re.search(r'JSON\.stringify\([^)]*_accessToken', s)   # …and is never serialised
assert '"token", "--json"' in s                           # the broker, not a refresh token of our own
print("SECRET-OK")
PY
check "state files hold no token/password; token only via ewe-auth" "grep -q SECRET-OK '$SB/secret.chk'" || cat "$SB/secret.chk"
check "legacy state paths kept (mail-state.json, google-mail.json)" "grep -q 'quickshell/mail-state.json' Inbox.qml && grep -q 'quickshell/google-mail.json' Inbox.qml"

# 5. Rule 8 — Theme tokens only ───────────────────────────────────────────────
check "no raw hex colours in QML" "! grep -nE '#[0-9a-fA-F]{3,8}\\b' *.qml"
check "no numeric durations in QML" "! grep -nE 'duration: *[0-9]' *.qml"
check "no core-internal singletons (Google, Mail, Globals, HyprMon) in code" "! grep -vE '^\\s*//' *.qml | grep -nE '\\b(Google|Mail|Globals|HyprMon)\\.'"

# 6. the ewe tool, when this box has it (the shell's own validator) ───────────
tool="${EWE_PLUGIN_TOOL:-$(command -v ewe-plugin || true)}"
if [ -n "$tool" ]; then
  # sandboxed HOME, and no compositor signature: the tool must never touch the live shell
  check "ewe-plugin validate --first-party" "env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY HOME='$SB/home' XDG_CONFIG_HOME='$SB/home/.config' XDG_STATE_HOME='$SB/home/.local/state' XDG_DATA_HOME='$SB/home/.local/share' EWE_PAYLOAD_PLUGINS='$SB/payload' '$tool' validate . --first-party >/dev/null 2>&1"
fi

echo "ewe.mail: $pass passed, $failn failed"
[ "$failn" = 0 ]
