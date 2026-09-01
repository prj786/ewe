#!/usr/bin/env bash
# [network.ssh] contract test — definitions sync, the user's own lines are
# sacred. Everything sandboxed: fake ssh config, fake nmcli on PATH, temp XDG.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export EWE_CONF_SSH_CONFIG="$WORK/ssh-config"
mkdir -p "$WORK/config/ewe" "$WORK/bin"

# fake nmcli: one openvpn profile + one wireguard; records `add` calls
cat > "$WORK/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "-t -f NAME,TYPE connection show")
        printf 'office:vpn\nwg-home:wireguard\nWiFi-1:802-11-wireless\n' ;;
    "-t -g vpn.service-type,vpn.data connection show office")
        printf 'org.freedesktop.NetworkManager.openvpn\nremote = vpn.example.com, port = 1194\n' ;;
    "-t -f NAME connection show")
        printf 'WiFi-1\n' ;;   # fresh machine: no VPNs yet
    "connection add "*)
        echo "$*" >> "${EWE_TEST_NMCLI_LOG:?}"; exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/nmcli"
export PATH="$WORK/bin:$PATH"
export EWE_TEST_NMCLI_LOG="$WORK/nmcli-add.log"

EC="$HERE/bin/ewe-conf"
fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }

# machine A: a hand-written ssh config
cat > "$WORK/ssh-config" <<'EOF'
# my own comment stays
Host *
    ServerAliveInterval 60

Host work
    HostName 10.0.0.5
    User scubba
    Port 2222
    IdentityFile ~/.ssh/id_work

Host pi
    HostName 192.168.1.2
    User pi
EOF

# 1 · import adopts the single-name hosts (never the wildcard) + the VPN defs
"$EC" import >/dev/null
h=$("$EC" get network.ssh.hosts)
grep -q '"host": "work"' <<<"$h" && grep -q '"host": "pi"' <<<"$h" || fail "hosts not adopted: $h"
grep -q '"Host \*"' <<<"$h" && fail "wildcard adopted"
v=$("$EC" get network.vpn)
grep -q '"name": "office"' <<<"$v" && grep -q 'openvpn' <<<"$v" || fail "vpn not adopted: $v"
grep -q '"wg-home"' <<<"$v" || fail "wireguard name not recorded: $v"
grep -qi 'secret\|password' <<<"$v" && fail "secrets leaked into vpn defs"
ok "import adopts ssh hosts + vpn definitions (no wildcards, no secrets)"

# 2 · apply on the SAME machine: hosts already defined outside the block are
#     skipped — the config gains only the empty managed block, own lines intact
"$EC" apply --only network --no-hooks
grep -q 'my own comment stays' "$WORK/ssh-config" || fail "user comment lost"
grep -q 'ServerAliveInterval 60' "$WORK/ssh-config" || fail "wildcard block lost"
[ "$(grep -c 'Host work' "$WORK/ssh-config")" = 1 ] || fail "duplicated host"
grep -q '>>> ewe managed hosts' "$WORK/ssh-config" || fail "managed block missing"
ok "apply never duplicates or touches the user's own lines"

# 3 · fresh machine: empty ssh config → the managed block carries every host
export EWE_CONF_SSH_CONFIG="$WORK/ssh-config-fresh"
"$EC" apply --only network --no-hooks
grep -q 'Host work' "$WORK/ssh-config-fresh" && grep -q 'HostName 10.0.0.5' "$WORK/ssh-config-fresh" \
    && grep -q 'Port 2222' "$WORK/ssh-config-fresh" && grep -q 'Host pi' "$WORK/ssh-config-fresh" \
    || fail "restored config incomplete: $(cat "$WORK/ssh-config-fresh")"
[ "$(stat -c %a "$WORK/ssh-config-fresh")" = 600 ] || fail "ssh config not 0600"
ok "fresh machine gets every host back, mode 0600"

# 4 · fresh machine: the missing openvpn profile is recreated (skeleton),
#     wireguard is not (its peers hold key material)
grep -q 'con-name office' "$WORK/nmcli-add.log" || fail "openvpn profile not recreated"
grep -q 'vpn-type openvpn' "$WORK/nmcli-add.log" || fail "vpn-type wrong: $(cat "$WORK/nmcli-add.log")"
grep -q 'wg-home' "$WORK/nmcli-add.log" && fail "wireguard wrongly recreated"
ok "restore recreates plugin VPNs only, as skeletons"

# 5 · re-apply is idempotent
before=$(cat "$WORK/ssh-config-fresh")
"$EC" apply --only network --no-hooks
[ "$before" = "$(cat "$WORK/ssh-config-fresh")" ] || fail "re-apply churned the file"
ok "re-apply is a no-op"

echo "ALL PASS"
