#!/usr/bin/env bash
# ewe-remote tests (RFC-009) — two "computers" on one box, a REAL sshd and
# ssh, nothing of the live machine touched: every state dir is a sandbox,
# EWE_REMOTE_NO_SYSTEMD=1 runs sshd as a plain child (no systemctl --user),
# the account and Tailscale are fakes (not signed in / not installed), and
# nothing is ever killed by name — only by the pids this test started.
#
# Covers: share on/off, the code (8 digits, single use), the pairing key's
# forced command (no shell, no forwarding), SPAKE2 pairing — wrong code
# counted and refused, right code accepted, the host key pinned —, the
# 5-second gap, ssh through the generated ssh_config (with the desktop's
# XDG_RUNTIME_DIR), a SOCKS tunnel that resolves names on the far side,
# who-is-connected, revoke (ends the tunnel, refuses the next one), forget,
# and JSON + exit 0 for every verb.
#
# Needs: openssh (ssh, sshd), python-spake2, curl. EWE_REMOTE_PYTHON picks the
# interpreter (a venv with spake2 on a dev box).
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$(pwd)
PY=${EWE_REMOTE_PYTHON:-python3}
if ! "$PY" -c 'import spake2' 2>/dev/null; then echo "SKIP: python-spake2 is not installed"; exit 0; fi
for t in ssh sshd curl ssh-keygen ss; do
    command -v "$t" >/dev/null || { echo "SKIP: $t is not installed"; exit 0; }
done

SB=$(mktemp -d)
PIDS=()
cleanup() {
    for d in "$SB/a" "$SB/b"; do
        [ -f "$d/run/sshd-test.pid" ] && kill -- "-$(cat "$d/run/sshd-test.pid")" 2>/dev/null
        [ -f "$d/run/tunnels.json" ] && "$PY" -c "
import json,os,signal
for v in json.load(open('$d/run/tunnels.json')).values():
    try: os.killpg(v['pid'], signal.SIGTERM)
    except OSError: pass" 2>/dev/null
    done
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
    rm -rf "$SB"
}
trap cleanup EXIT

free_port() { "$PY" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
PORT_A=$(free_port)

# the account: tests/mock-nextcloud.py, signed in as its tester (both
# computers on ONE account — that's the point)
NC_PORT=$(free_port)
"$PY" "$REPO/tests/mock-nextcloud.py" "$NC_PORT" "$SB/nc.json" >"$SB/nc.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$NC_PORT) 2>/dev/null && break; sleep 0.1; done
# fakes: ewe-cloud hands out the mock's app password, no Tailscale, ewe-conf
# records what it's told, `ip` shows one "LAN" address that is loopback (the
# test sshd listens there only — nothing is exposed on the real network)
mkdir -p "$SB/bin"
printf '#!/bin/sh\necho "{\\"ok\\": true, \\"server\\": \\"http://127.0.0.1:%s\\", \\"user\\": \\"tester\\", \\"token\\": \\"app-pass-0123456789abcdef\\"}"\n' "$NC_PORT" > "$SB/bin/ewe-cloud"
printf '#!/bin/sh\n[ "$1" = set ] && echo "$2=$3" >> "${EWE_REMOTE_DIR}/conf.log"\nexit 1\n' > "$SB/bin/ewe-conf"
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/notify-send"
printf '#!/bin/sh\necho %s\n' "'[{\"ifname\":\"eth0\",\"addr_info\":[{\"family\":\"inet\",\"local\":\"127.0.0.1\",\"prefixlen\":8,\"scope\":\"global\"}]}]'" > "$SB/bin/ip"
chmod +x "$SB/bin/"*

envfile() {  # $1 = a|b, $2 = id, $3 = name, $4 = port
    cat > "$SB/$1.env" <<EOF
export EWE_REMOTE_DIR="$SB/$1/data" EWE_REMOTE_RUN="$SB/$1/run"
export EWE_REMOTE_MACHINE_ID="$2" EWE_REMOTE_NAME="$3" EWE_REMOTE_PORT="$4"
export EWE_REMOTE_NO_SYSTEMD=1 EWE_REMOTE_LAX_MODES=1 EWE_REMOTE_NO_NOTIFY=1 EWE_REMOTE_LISTEN=127.0.0.1
export EWE_REMOTE_TAILSCALE="$SB/bin/no-tailscale-here"
export EWE_REMOTE_SELF="$SB/$1/self.sh"
export PATH="$SB/bin:\$PATH"
EOF
    mkdir -p "$SB/$1"
    # the forced command runs in sshd's bare environment — this wrapper IS
    # "ewe-remote" on that computer
    printf '#!/bin/sh\n. "%s"\nexec "%s" "%s" "$@"\n' "$SB/$1.env" "$PY" "$REPO/bin/ewe-remote" > "$SB/$1/self.sh"
    chmod +x "$SB/$1/self.sh"
}
ID_A=aaaaaaaaaaaaaaaa; ID_B=bbbbbbbbbbbbbbbb
envfile a "$ID_A" work-pc "$PORT_A"
envfile b "$ID_B" home-laptop 1   # B never shares
A() { "$SB/a/self.sh" "$@"; }
B() { "$SB/b/self.sh" "$@"; }

pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }
j() { "$PY" -c "import json,sys; j=json.loads(sys.stdin.read()); $1"; }
ME=$(id -un)

# ── share on ─────────────────────────────────────────────────────────────────
R=$(A share on)
check "share on: ok + sharing" "echo '$R' | j 'assert j[\"ok\"] and j[\"sharing\"] is True'"
CODE=$(echo "$R" | j 'print(j["code"])')
check "share on: an 8-digit code" "[[ '$CODE' =~ ^[0-9]{8}$ ]]"
check "share on: published to the account" "echo '$R' | j 'assert j[\"published\"] is True' && j 'assert any(k.endswith(\"remote/$ID_A.json\") for k in j[\"files\"])' < '$SB/nc.json'"
check "share on: the port answers" "(exec 3<>/dev/tcp/127.0.0.1/$PORT_A) 2>/dev/null"
check "share on: ewe.conf remote.sharing true (through ewe-conf)" "grep -q 'remote.sharing=true' '$SB/a/data/conf.log'"
check "share on: private files are 0600, the dir 0700" "[ \$(stat -c %a '$SB/a/data') = 700 ] && [ \$(stat -c %a '$SB/a/data/code') = 600 ] && [ \$(stat -c %a '$SB/a/data/authorized_keys') = 600 ]"
check "sshd_config: key-only, no PAM, the desktop env" "grep -qx 'PasswordAuthentication no' '$SB/a/data/sshd_config' && grep -qx 'UsePAM no' '$SB/a/data/sshd_config' && grep -q '^SetEnv XDG_RUNTIME_DIR=/run/user/' '$SB/a/data/sshd_config'"
R=$(A status --offline)
check "status: sharing + code + port" "echo '$R' | j 'assert j[\"this\"][\"sharing\"] and j[\"this\"][\"code\"]==\"$CODE\" and j[\"this\"][\"port\"]==$PORT_A and j[\"tailscale\"][\"installed\"] is False'"

# ── the pairing key can only pair ────────────────────────────────────────────
B code >/dev/null   # creates B's data dir
printf '%s\n' "$("$PY" -c "import importlib.machinery,importlib.util as u; l=importlib.machinery.SourceFileLoader('r','$REPO/bin/ewe-remote'); s=u.spec_from_loader('r',l); m=u.module_from_spec(s); l.exec_module(m); print(m.PAIRING_PRIVATE)")" > "$SB/pk"; chmod 600 "$SB/pk"
SSHO=(-F /dev/null -i "$SB/pk" -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "$PORT_A")
OUT=$(timeout 15 ssh "${SSHO[@]}" -T "$ME@127.0.0.1" 'echo PWNED' </dev/null 2>&1)
check "pairing key: a command runs pair-serve, never a shell" "! echo '$OUT' | grep -q PWNED"
sleep 5.2
SOCKP=$(free_port)
timeout 20 ssh "${SSHO[@]}" -N -D "127.0.0.1:$SOCKP" "$ME@127.0.0.1" </dev/null >/dev/null 2>&1 &
PIDS+=($!); sleep 2
check "pairing key: no forwarding (SOCKS through it fails)" "! curl -s --max-time 5 --socks5-hostname 127.0.0.1:$SOCKP -o /dev/null http://127.0.0.1:$PORT_A/"
kill "${PIDS[-1]}" 2>/dev/null
sleep 5.2

# ── pairing ──────────────────────────────────────────────────────────────────
WRONG=$(printf '%08d' $(( (10#$CODE + 1) % 100000000 )))
R=$(B pair "$ME@127.0.0.1:$PORT_A" "$WRONG")
check "pair: a wrong code is refused" "echo '$R' | j 'assert not j[\"ok\"] and j[\"error\"]==\"wrong-code\", j'"
check "pair: the failure is counted on the host" "j 'assert j[\"fails\"]==1' < '$SB/a/data/pairing.json'"
check "pair: nothing got in" "! grep -q 'ewe-remote:$ID_B' '$SB/a/data/authorized_keys'"
R=$(B pair "$ME@127.0.0.1:$PORT_A" "$CODE")
check "pair: too quick after a failure → busy" "echo '$R' | j 'assert not j[\"ok\"] and j[\"error\"]==\"busy\", j'"
sleep 5.2
R=$(B status --refresh)
check "account: B sees work-pc, shared and online, not yet paired" "echo '$R' | j 'c=[c for c in j[\"computers\"] if c[\"id\"]==\"$ID_A\"][0]; assert c[\"name\"]==\"work-pc\" and c[\"sharing\"] and c[\"online\"] and not c[\"paired\"], c'"
check "account: B does not list itself" "echo '$R' | j 'assert all(c[\"id\"]!=\"$ID_B\" for c in j[\"computers\"])'"
R=$(B pair work-pc "${CODE:0:4} ${CODE:4:4}")
check "pair: by NAME from the account, the right code (typed with a space) is accepted" "echo '$R' | j 'assert j[\"ok\"] and j[\"computer\"][\"id\"]==\"$ID_A\" and j[\"computer\"][\"name\"]==\"work-pc\", j'"
check "pair: the host now allows B, tagged with its id + name" "grep -q 'ewe-remote:$ID_B:home-laptop:' '$SB/a/data/authorized_keys'"
check "pair: the host key is pinned under its alias" "grep -q '^ewe-$ID_A ssh-ed25519 ' '$SB/b/data/known_hosts' && [ \"\$(awk '{print \$3}' '$SB/b/data/known_hosts')\" = \"\$(awk '{print \$2}' '$SB/a/data/host_ed25519.pub')\" ]"
NEWCODE=$(A code | j 'print(j["code"])')
check "pair: the code is single-use (changed)" "[ '$NEWCODE' != '$CODE' ]"
check "pair: failures reset" "j 'assert j[\"fails\"]==0' < '$SB/a/data/pairing.json'"
check "pair: B's private key never left B" "! grep -rqF \"\$(sed -n 4p '$SB/b/data/id_ed25519')\" '$SB/a/data'"

# ── using it ─────────────────────────────────────────────────────────────────
OUT=$(timeout 15 ssh -F "$SB/b/data/ssh_config" "ewe-$ID_A" 'echo REMOTE_OK; echo "rt=$XDG_RUNTIME_DIR"' </dev/null 2>&1)
check "ssh: the generated ssh_config logs in" "echo '$OUT' | grep -qx REMOTE_OK"
check "ssh: the session has the desktop's XDG_RUNTIME_DIR" "echo '$OUT' | grep -qx 'rt=/run/user/$(id -u)'"
OUT=$(timeout 15 ssh -F "$SB/b/data/ssh_config" work-pc 'echo BY_NAME' </dev/null 2>&1)
check "ssh: the name works as an alias" "echo '$OUT' | grep -qx BY_NAME"
# a web page only "the far side" can see: an HTTP server on loopback
WEBP=$(free_port); mkdir -p "$SB/www"; echo far-side > "$SB/www/x.txt"
(cd "$SB/www" && exec "$PY" -m http.server "$WEBP" --bind 127.0.0.1 >/dev/null 2>&1) &
PIDS+=($!); sleep 1
R=$(B tunnel "$ID_A")
check "tunnel: SOCKS comes up" "echo '$R' | j 'assert j[\"ok\"] and j[\"socks\"].startswith(\"127.0.0.1:\")'"
SOCKS=$(echo "$R" | j 'print(j["socks"])')
check "tunnel: a page through it (name resolved on the far side)" "[ \"\$(curl -s --max-time 8 --socks5-hostname $SOCKS http://localhost:$WEBP/x.txt)\" = far-side ]"
R2=$(B tunnel "$ID_A")
check "tunnel: a second call reuses the live one" "echo '$R2' | j 'assert j[\"reused\"] and j[\"socks\"]==\"$SOCKS\"'"
check "tunnels: listed" "B tunnels | j 'assert any(t[\"id\"]==\"$ID_A\" for t in j[\"tunnels\"])'"
R=$(A status --offline)
check "host status: B is connected now (from the auth log + ss)" "echo '$R' | j 'assert any(s[\"id\"]==\"$ID_B\" for s in j[\"this\"][\"sessions\"]), j[\"this\"][\"sessions\"]'"
check "host status: B is allowed" "echo '$R' | j 'assert any(a[\"id\"]==\"$ID_B\" and a[\"name\"]==\"home-laptop\" for a in j[\"this\"][\"allowed\"])'"
R=$(B status --offline)
check "joiner status: A is paired, with its tunnel" "echo '$R' | j 'c=[c for c in j[\"computers\"] if c[\"id\"]==\"$ID_A\"][0]; assert c[\"paired\"] and c[\"tunnel\"]'"

# ── revoke / forget / off ────────────────────────────────────────────────────
R=$(A revoke "$ID_B")
check "revoke: removed + its session ended" "echo '$R' | j 'assert j[\"revoked\"] and j[\"ended\"]>=1, j'"
sleep 1
check "revoke: the tunnel is dead" "! curl -s --max-time 4 --socks5-hostname $SOCKS -o /dev/null http://localhost:$WEBP/x.txt"
R=$(B tunnel "$ID_A")
check "revoke: the next tunnel is refused (not-allowed)" "echo '$R' | j 'assert not j[\"ok\"] and j[\"error\"]==\"not-allowed\", j'"
R=$(B forget "$ID_A")
check "forget: B drops A" "echo '$R' | j 'assert j[\"forgotten\"]' && ! grep -q 'ewe-$ID_A' '$SB/b/data/known_hosts' && ! grep -q 'Host ewe-$ID_A' '$SB/b/data/ssh_config'"
R=$(B terminal "$ID_A")
check "terminal: not paired → a clear error" "echo '$R' | j 'assert j[\"error\"]==\"not-paired\"'"
R=$(A share off)
check "share off" "echo '$R' | j 'assert j[\"ok\"] and j[\"sharing\"] is False' && grep -q 'remote.sharing=false' '$SB/a/data/conf.log'"
sleep 0.5
R=$(B status --refresh)
check "account: after share off B sees work-pc not shared" "echo '$R' | j 'c=[c for c in j[\"computers\"] if c[\"id\"]==\"$ID_A\"][0]; assert c[\"sharing\"] is False, c'"
check "share off: the port is closed" "! (exec 3<>/dev/tcp/127.0.0.1/$PORT_A) 2>/dev/null"

# ── rule 5: JSON + exit 0 for every verb, even nonsense ──────────────────────
for v in "status --offline" "code" "tunnels" "publish" "nonsense" "pair x 1" "pair nobody 12345678" "tunnel nobody" "revoke $ID_B" "disconnect $ID_B" "untunnel $ID_A" "forget $ID_A"; do
    # shellcheck disable=SC2086
    O=$(B $v); rc=$?
    check "json+exit0: $v" "[ $rc = 0 ] && echo '$O' | j 'assert isinstance(j, dict) and \"ok\" in j'"
done

echo "ewe-remote: $pass passed, $failn failed"
[ "$failn" = 0 ]
