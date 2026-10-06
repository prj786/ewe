#!/usr/bin/env bash
# ewe.slack tests — no compositor, no Slack account: the manifest, the IPC
# verbs, the helper's offline contract, that no token can reach QML or a
# file, and Rule 8 (Theme tokens only).
set -euo pipefail
cd "$(dirname "$0")"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

python3 - <<'PY' > "$SB/manifest.chk" 2>&1 || true
import json, os, re
m = json.load(open("manifest.json"))
assert m["apiVersion"] == 3 and m["schemaVersion"] == 1 and m["id"] == "ewe.slack"
assert set(m["kinds"]) == {"service", "desktop-widget", "panel"}
assert m["desktopWidget"]["layer"] == "desktop"
assert re.match(r"^ic[A-Z]", m["icon"])
for f in m["entryPoints"].values(): assert os.path.isfile(f), f
for s in m["settings"]: assert re.match(r"^[a-z][a-z0-9_]{0,31}$", s["key"]), s["key"]
print("MANIFEST-OK")
PY
check "manifest: ewe.slack, API 3, service + desktop-widget + panel, snake_case settings" "grep -q MANIFEST-OK '$SB/manifest.chk'" || cat "$SB/manifest.chk"
check "qmldir: SlackInbox singleton, SlackAvatar, SlackRow" "grep -q '^singleton SlackInbox 1.0 SlackInbox.qml' qmldir && grep -q '^SlackAvatar 1.0 SlackAvatar.qml' qmldir && grep -q '^SlackRow 1.0 SlackRow.qml' qmldir"
check "IPC target ewe.slack: refresh status open connect" "grep -q 'target: \"ewe.slack\"' Service.qml && grep -q 'function refresh()' Service.qml && grep -q 'function status(): string' Service.qml && grep -q 'function open()' Service.qml && grep -q 'function connect()' Service.qml"

check "helper compiles" "python3 -m py_compile slack-unread.py"
# no keyring entry in a sandboxed session bus → a clean no-token answer
out="$(env DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent PATH="$SB/bin:$PATH" python3 slack-unread.py --state-dir "$SB/state" 2>/dev/null || true)"
check "helper without a token answers {ok:false,error:no-token}" "echo '$out' | python3 -c 'import json,sys; j=json.load(sys.stdin); assert j==dict(ok=False,error=\"no-token\")'"

check "no token in QML (helper reads the keyring itself)" "! grep -nE 'xoxp-[A-Za-z0-9]|secret-tool|Authorization' *.qml"
check "the token reaches the helper on stdin, never argv" "grep -q 'stdinEnabled: true' SlackInbox.qml && grep -q '_connect.write(si._pendingToken' SlackInbox.qml && ! grep -nE 'command:.*(_pendingToken|input\.text)' *.qml"
check "Connect field is a password field" "grep -q 'echoMode: TextInput.Password' Setup.qml"
for bad in "hello" "xoxb-123"; do
  o="$(echo "$bad" | env DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent python3 slack-unread.py --connect --state-dir "$SB/c")"
  check "--connect refuses '$bad' before any network or keyring" "echo '$o' | grep -q '\"ok\": false'"
done
check "helper never prints or stores the token" "! grep -nE 'print\\(.*tok|json\\.dump\\(.*tok' slack-unread.py"

check "no raw hex colours in QML" "! grep -nE '#[0-9a-fA-F]{3,8}\\b' *.qml"
check "no numeric durations in QML" "! grep -nE 'duration: *[0-9]' *.qml"
check "no core-internal singletons in code" "! grep -vE '^\\s*//' *.qml | grep -nE '\\b(Google|Mail|Globals|HyprMon)\\.'"

tool="${EWE_PLUGIN_TOOL:-$(command -v ewe-plugin || true)}"
if [ -n "$tool" ]; then
  check "ewe-plugin validate --first-party" "env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY HOME='$SB/home' XDG_CONFIG_HOME='$SB/home/.config' XDG_STATE_HOME='$SB/home/.local/state' XDG_DATA_HOME='$SB/home/.local/share' EWE_PAYLOAD_PLUGINS='$SB/payload' '$tool' validate . --first-party >/dev/null 2>&1"
fi

echo "ewe.slack: $pass passed, $failn failed"
[ "$failn" = 0 ]
