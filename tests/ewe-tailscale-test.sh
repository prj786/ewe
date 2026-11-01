#!/usr/bin/env bash
# ewe-tailscale: status parsing (Running, relayed, NeedsLogin, not installed,
# daemon down, not the operator, exit node offline, health messages) and the
# write verbs (setup through pkexec, up with a sign-in URL / already running /
# the "mention all non-default flags" refusal / a hang, reconnect, down,
# logout, exit-node off) — every one prints ONE JSON object and exits 0.
#
# Everything runs against FAKE tailscale / systemctl / pkexec / xdg-open on a
# PATH that holds nothing else (plus a few coreutils), so the host's real
# tailscaled — and the network this machine is on — is never touched.
set -u
cd "$(dirname "$0")/.."
TOOL="$PWD/bin/ewe-tailscale"
PY="$(command -v python3)" || { echo "skip: needs python3"; exit 0; }
fail=0
ok() { echo "ok    $*"; }
# failures are also recorded in a file: ts() runs inside $( ), a subshell
no() { echo "FAIL  $*" >&2; echo "$*" >>"${FAILED:-/dev/null}"; fail=1; }

"$PY" -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$TOOL" && ok "ewe-tailscale parses" || no "ewe-tailscale does not parse"

SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
FAILED="$SB/failed"
mkdir -p "$SB/bin" "$SB/sys" "$SB/fx" "$SB/log" "$SB/bin-nots"
for t in sh cat sleep touch rm; do ln -s "$(command -v "$t")" "$SB/sys/$t"; done
ME=$(id -un)
export FAKE_LOG="$SB/log" FAKE_FX="$SB/fx" FAKE_USER="$ME"

# ── fixtures: tailscale status --json / debug prefs ──────────────────────────
"$PY" - "$SB/fx" "$ME" <<'EOF'
import json, sys, os
fx, me = sys.argv[1], sys.argv[2]
def w(name, obj):
    json.dump(obj, open(os.path.join(fx, name), "w"), indent=1)
self_ = {"HostName": "desk", "DNSName": "desk.tail1234.ts.net.", "Online": True,
         "TailscaleIPs": ["100.101.102.103", "fd7a:115c:a1e0::1"], "Relay": "fra"}
def peer(i, name, online=True, active=False, cur="", exit=False):
    return {"ID": "n%d" % i, "HostName": name, "DNSName": name + ".tail1234.ts.net.",
            "Online": online, "Active": active, "CurAddr": cur, "Relay": "fra",
            "ExitNode": exit, "TailscaleIPs": ["100.64.0.%d" % i]}
base = {"BackendState": "Running", "AuthURL": "", "Health": [], "Self": self_,
        "TailscaleIPs": self_["TailscaleIPs"], "ExitNodeStatus": None}
running = dict(base, Peer={"a": peer(1, "laptop", active=True, cur="192.168.1.20:41641"),
                           "b": peer(2, "phone"), "c": peer(3, "nas", online=False)})
w("running.json", running)
w("relay.json", dict(base, Peer={"a": peer(1, "laptop", active=True), "b": peer(2, "phone", active=True)}))
w("needslogin.json", dict(base, BackendState="NeedsLogin", AuthURL="https://login.tailscale.com/a/abc123",
                          Self={}, TailscaleIPs=[], Peer={}))
w("exitoffline.json", dict(base, Peer={"a": peer(9, "exit", online=False, exit=True)},
                           ExitNodeStatus={"ID": "n9", "Online": False, "TailscaleIPs": ["100.64.0.9/32"]}))
w("health.json", dict(running, Health=[
    "Tailscale could not connect to the 'fra' relay server. Your Internet connection might be down, or the server might be temporarily unavailable.",
    "This network might require you to log in using your web browser."]))
w("stopped.json", dict(base, BackendState="Stopped", Peer={}))
prefs = {"ControlURL": "https://controlplane.tailscale.com", "RouteAll": False, "CorpDNS": True,
         "WantRunning": True, "LoggedOut": False, "OperatorUser": me, "ExitNodeID": "", "ExitNodeIP": "",
         "RunSSH": True}
w("prefs.json", prefs)
w("prefs-noop.json", dict(prefs, OperatorUser=""))
EOF

# ── the fakes ─────────────────────────────────────────────────────────────────
cat >"$SB/bin/tailscale" <<'EOF'
#!/bin/sh
# mode: running relay needslogin exitoffline health stopped nodaemon notoperator
# hang revert. `systemctl enable --now` (fake) and `set --operator=` leave
# markers in $FAKE_LOG, so `setup` moves a "nodaemon" machine forward.
echo "tailscale $*" >>"$FAKE_LOG/tailscale"
mode="${FAKE_TS_MODE:-running}"
up=1; op=1
if [ "$mode" = nodaemon ]; then [ -e "$FAKE_LOG/started" ] || up=0; [ -e "$FAKE_LOG/operator" ] || op=0; fi
[ "$mode" = notoperator ] && { [ -e "$FAKE_LOG/operator" ] || op=0; }
case "$1" in
    status)
        [ $up = 1 ] || { echo "failed to connect to local tailscaled; it doesn't appear to be running (sudo systemctl start tailscaled ?)" >&2; exit 1; }
        case "$mode" in
            nodaemon) cat "$FAKE_FX/needslogin.json" ;;
            notoperator|hang|revert) cat "$FAKE_FX/running.json" ;;
            *) cat "$FAKE_FX/$mode.json" ;;
        esac ;;
    debug)
        [ $up = 1 ] || exit 1
        if [ $op = 1 ]; then cat "$FAKE_FX/prefs.json"; else cat "$FAKE_FX/prefs-noop.json"; fi ;;
    set)
        case "$2" in --operator=*) touch "$FAKE_LOG/operator" ;; esac ;;
    up)
        case "$mode" in
            needslogin|nodaemon)
                printf '{\n\t"AuthURL": "https://login.tailscale.com/a/abc123",\n\t"BackendState": "NeedsLogin"\n}\n'
                exec sleep 30 ;;
            hang) exec sleep 30 ;;
            revert)
                case " $* " in *" --ssh "*) printf '{\n\t"BackendState": "Running"\n}\n'; exit 0 ;; esac
                printf "Error: changing settings via 'tailscale up' requires mentioning all\nnon-default flags. To proceed, either re-run your command with --reset or\nuse the command below to explicitly mention the current value of\nall non-default settings:\n\n\ttailscale up --accept-routes=false --operator=%s --ssh\n\n" "$FAKE_USER" >&2
                exit 1 ;;
            *) printf '{\n\t"BackendState": "Running"\n}\n' ;;
        esac ;;
esac
exit 0
EOF
cat >"$SB/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$FAKE_LOG/systemctl"
st=0; [ -e "$FAKE_LOG/started" ] && st=1
case "$1" in
    is-enabled) if [ "${FAKE_TS_MODE:-}" = nodaemon ] && [ $st = 0 ]; then echo disabled; exit 1; fi; echo enabled ;;
    is-active)  if [ "${FAKE_TS_MODE:-}" = nodaemon ] && [ $st = 0 ]; then echo inactive; exit 3; fi; echo active ;;
    enable)     touch "$FAKE_LOG/started" ;;
esac
exit 0
EOF
cat >"$SB/bin/pkexec" <<'EOF'
#!/bin/sh
echo "pkexec $1 $2" >>"$FAKE_LOG/pkexec"
[ -n "${FAKE_PKEXEC_RC:-}" ] && exit "$FAKE_PKEXEC_RC"
exec "$@"
EOF
cat >"$SB/bin/xdg-open" <<'EOF'
#!/bin/sh
echo "$*" >>"$FAKE_LOG/xdg-open"
EOF
chmod +x "$SB/bin/"*
for f in systemctl pkexec xdg-open; do ln -s "$SB/bin/$f" "$SB/bin-nots/$f"; done

FULLPATH="$SB/bin:$SB/sys"
reset_log() { rm -f "$SB/log/"*; }
# ts <mode> <args…> → stdout of the tool; asserts JSON + exit 0 for every call
ts() {
    local mode="$1"; shift
    local o rc
    o=$(FAKE_TS_MODE="$mode" PATH="${TS_PATH:-$FULLPATH}" "$PY" "$TOOL" "$@" 2>"$SB/stderr"); rc=$?
    [ "$rc" = 0 ] || no "[$mode] ewe-tailscale $* exited $rc"
    printf '%s' "$o" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, dict) and "ok" in d' 2>/dev/null \
        || no "[$mode] ewe-tailscale $* did not print one JSON object: $o"
    printf '%s' "$o"
}
# q <json> <python expression over d> → its value
q() { printf '%s' "$1" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); v=eval(sys.argv[1]); print(json.dumps(v) if not isinstance(v, str) else v)' "$2"; }
want() { # want "<label>" "<json>" "<expr>" "<expected>"
    local got; got=$(q "$2" "$3")
    [ "$got" = "$4" ] && ok "$1" || no "$1: $3 = $got, wanted $4"
}

# ── status ───────────────────────────────────────────────────────────────────
o=$(TS_PATH="$SB/bin-nots:$SB/sys" ts running status)
want "not installed → installed:false, ok:true" "$o" '[d["ok"], d["installed"]]' '[true, false]'

o=$(ts running status)
want "running: state" "$o" 'd["state"]' Running
want "running: self" "$o" '[d["self"]["ip4"], d["self"]["ip6"], d["self"]["dns"], d["self"]["name"]]' \
    '["100.101.102.103", "fd7a:115c:a1e0::1", "desk.tail1234.ts.net", "desk"]'
want "running: operator, no setup needed" "$o" '[d["operator_ok"], d["needs_setup"], d["enabled"], d["running"]]' '[true, false, true, true]'
want "running: peers counted" "$o" 'd["peers"]' '{"total": 3, "online": 2}'
want "running: a direct path → not relay-only" "$o" 'd["relay_only"]' false
want "running: no exit node, no health, prefs read" "$o" '[d["exit_node"], d["health"], d["accept_routes"], d["accept_dns"], d["login_server"]]' \
    '[null, [], false, true, "https://controlplane.tailscale.com"]'

o=$(ts relay status)
want "relayed: every active peer without a direct path → relay_only" "$o" 'd["relay_only"]' true

o=$(ts needslogin status)
want "NeedsLogin: state + login_url" "$o" '[d["state"], d["login_url"]]' '["NeedsLogin", "https://login.tailscale.com/a/abc123"]'

o=$(ts exitoffline status)
want "exit node offline" "$o" 'd["exit_node"]' '{"name": "exit", "ip": "100.64.0.9", "online": false}'

o=$(ts health status)
want "health messages passed through" "$o" '[len(d["health"]), "relay server" in d["health"][0]]' '[2, true]'

o=$(ts stopped status)
want "stopped (tailscale down) → state Stopped" "$o" 'd["state"]' Stopped

reset_log
o=$(ts nodaemon status)
want "daemon not running → NotRunning, needs setup" "$o" '[d["state"], d["running"], d["enabled"], d["needs_setup"]]' '["NotRunning", false, false, true]'

o=$(ts notoperator status)
want "not the operator → needs setup" "$o" '[d["operator_ok"], d["needs_setup"]]' '[false, true]'

# ── writes ───────────────────────────────────────────────────────────────────
reset_log
o=$(ts notoperator up)
want "up without operator → refused with needs-setup" "$o" '[d["ok"], d["code"]]' '[false, "needs-setup"]'
grep -q '^tailscale up' "$SB/log/tailscale" && no "up ran tailscale up although setup is missing" || ok "up never ran tailscale up before setup"

reset_log
o=$(FAKE_PKEXEC_RC=126 ts nodaemon setup)
want "setup: dismissed password dialog → cancelled" "$o" '[d["ok"], d["code"]]' '[false, "cancelled"]'

reset_log
o=$(ts nodaemon setup)
want "setup: ok, daemon up, operator set" "$o" '[d["ok"], d["running"], d["operator_ok"], d["state"]]' '[true, true, true, "NeedsLogin"]'
grep -q 'pkexec /bin/sh -c' "$SB/log/pkexec" && ok "setup: one pkexec" || no "setup did not go through pkexec"
grep -q 'systemctl enable --now tailscaled.service' "$SB/log/systemctl" && ok "setup: enable --now tailscaled" || no "setup did not enable tailscaled"
grep -q "tailscale set --operator=$ME\$" "$SB/log/tailscale" && ok "setup: operator = the calling user" || no "setup did not set the operator"
# a second press on a machine that is set up: no password prompt at all
rm -f "$SB/log/pkexec"
o=$(ts running setup)
want "setup again: nothing to do" "$o" '[d["ok"], d.get("already")]' '[true, true]'
[ ! -e "$SB/log/pkexec" ] && ok "setup again: no pkexec prompt" || no "setup asked for a password on a set-up machine"

reset_log
start=$(date +%s)
o=$(ts needslogin up)
el=$(( $(date +%s) - start ))
want "up: sign-in needed → login_url, opened" "$o" '[d["ok"], d["login_url"], d["opened"]]' '[true, "https://login.tailscale.com/a/abc123", true]'
[ "$el" -lt 10 ] && ok "up: returns once the URL is known (${el}s)" || no "up hung for ${el}s"
grep -q 'tailscale up --accept-routes=false --accept-dns=true --json' "$SB/log/tailscale" && ok "up: the safe flags" || no "up flags: $(grep '^tailscale up' "$SB/log/tailscale")"
grep -q 'https://login.tailscale.com/a/abc123' "$SB/log/xdg-open" && ok "up: browser opened on the sign-in page" || no "up did not open the browser"

reset_log
o=$(ts needslogin up --no-open)
want "up --no-open: URL only" "$o" '[d["login_url"], d["opened"]]' '["https://login.tailscale.com/a/abc123", false]'
[ ! -e "$SB/log/xdg-open" ] && ok "up --no-open: no browser" || no "up --no-open opened the browser"

reset_log
o=$(ts running up --login-server https://hs.example.com)
want "up when running → ok, Running" "$o" '[d["ok"], d["state"]]' '[true, "Running"]'
grep -q -- '--login-server=https://hs.example.com --json' "$SB/log/tailscale" && ok "up --login-server passed on" || no "login server not passed: $(grep '^tailscale up' "$SB/log/tailscale")"

reset_log
o=$(ts revert up)
want "up: 'mention all non-default flags' → tailscale's own command, once" "$o" '[d["ok"], d["state"]]' '[true, "Running"]'
[ "$(grep -c '^tailscale up' "$SB/log/tailscale")" = 2 ] && ok "up: retried exactly once" || no "up retries: $(grep -c '^tailscale up' "$SB/log/tailscale")"
grep -q "tailscale up --accept-routes=false --operator=$ME --ssh --json" "$SB/log/tailscale" && ok "up: retry keeps every setting (+ --json, no --reset)" || no "retry was: $(grep '^tailscale up' "$SB/log/tailscale" | tail -1)"
grep -q -- '--reset' "$SB/log/tailscale" && no "up used --reset" || ok "up: never --reset"

reset_log
start=$(date +%s)
o=$(EWE_TS_UP_TIMEOUT=2 ts hang up)
el=$(( $(date +%s) - start ))
want "up that never answers → ok, pending" "$o" '[d["ok"], d.get("pending")]' '[true, true]'
[ "$el" -lt 8 ] && ok "up: deadline honoured (${el}s)" || no "up overran its deadline: ${el}s"

reset_log
o=$(ts running reconnect)
want "reconnect → ok" "$o" 'd["ok"]' true
[ "$(grep -E '^tailscale (down|up)' "$SB/log/tailscale" | cut -d' ' -f2 | tr '\n' ' ')" = "down up " ] && ok "reconnect: down, then up" || no "reconnect order: $(grep -E '^tailscale (down|up)' "$SB/log/tailscale")"

reset_log
o=$(ts exitoffline exit-node off)
want "exit-node off → ok" "$o" 'd["ok"]' true
grep -q '^tailscale set --exit-node=$' "$SB/log/tailscale" && ok "exit-node off: set --exit-node=" || no "exit-node off ran: $(cat "$SB/log/tailscale")"

reset_log
o=$(ts running down); want "down → ok" "$o" 'd["ok"]' true
grep -q '^tailscale down$' "$SB/log/tailscale" && ok "down: tailscale down" || no "down did not run tailscale down"
o=$(ts running logout); want "logout → ok" "$o" 'd["ok"]' true
grep -q '^tailscale logout$' "$SB/log/tailscale" && ok "logout: tailscale logout" || no "logout did not run tailscale logout"

# ── the contract: every verb, every state → JSON, exit 0 ─────────────────────
for mode in running needslogin nodaemon notoperator exitoffline; do
    for args in "status" "setup" "up --no-open" "down" "logout" "reconnect --no-open" "exit-node off" \
                "exit-node" "bogus" "" "up --login-server ftp://x" "up --what"; do
        reset_log
        # shellcheck disable=SC2086
        FAKE_PKEXEC_RC=126 EWE_TS_UP_TIMEOUT=2 ts "$mode" $args >/dev/null
    done
done
TS_PATH="$SB/bin-nots:$SB/sys" ts running up >/dev/null
TS_PATH="$SB/bin-nots:$SB/sys" ts running setup >/dev/null
[ -s "$FAILED" ] && fail=1
[ "$fail" = 0 ] && ok "every verb in every state printed JSON and exited 0"

echo
[ "$fail" = 0 ] && echo "ewe-tailscale-test: PASS" || echo "ewe-tailscale-test: FAIL"
exit "$fail"
