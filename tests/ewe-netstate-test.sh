#!/usr/bin/env bash
# net-state.py (dotfiles/quickshell/scripts) — the one network reading the bar
# and Quick settings share. Fake nmcli / ip / ethtool and a fixture sysfs:
# a cable with link but no address yet (with its speed and what the NIC and
# the other end can do), a cable that carries traffic beating Wi-Fi, nmcli's
# escaped names, a VPN and Tailscale, NetworkManager down — and always ONE
# JSON object with exit 0. Nothing here talks to the real NetworkManager.
set -u
cd "$(dirname "$0")/.."
SCRIPT="$PWD/dotfiles/quickshell/scripts/net-state.py"
PY="$(command -v python3)" || { echo "skip: needs python3"; exit 0; }
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

"$PY" -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SCRIPT" && ok "net-state.py parses" || no "net-state.py does not parse"

SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/bin-noethtool" "$SB/sys" "$SB/net/enp3s0" "$SB/net/wlo1"
for t in sh cat; do ln -s "$(command -v "$t")" "$SB/sys/$t"; done
echo 1 >"$SB/net/enp3s0/carrier"; echo 100 >"$SB/net/enp3s0/speed"
echo 1 >"$SB/net/wlo1/carrier"
export EWE_NET_SYSFS="$SB/net"

# ── fakes: FAKE_NET picks the scenario ───────────────────────────────────────
cat >"$SB/bin/nmcli" <<'EOF'
#!/bin/sh
sc="${FAKE_NET:-waiting}"
[ "$sc" = nmdown ] && { echo "Error: NetworkManager is not running." >&2; exit 8; }
case "$*" in
    *"device status")
        case "$sc" in
            waiting) printf '%s\n' 'wlo1:wifi:connected:full:full:Café\: 5G' 'enp3s0:ethernet:connecting (getting IP configuration):none:none:Wired connection 1' 'lo:loopback:connected (externally):unknown:unknown:lo' ;;
            wiredup) printf '%s\n' 'enp3s0:ethernet:connected:limited:full:Wired connection 1' 'wlo1:wifi:connected:full:full:786  ' ;;
            vpn)     printf '%s\n' 'wlo1:wifi:connected:full:full:home' 'ppp0:ppp:connected (externally):limited:unknown:ppp0' 'tailscale0:tun:connected (externally):limited:limited:tailscale0' ;;
        esac ;;
    *"networking connectivity") case "$sc" in vpn) echo limited ;; *) echo full ;; esac ;;
    *"device show enp3s0")
        printf '%s\n' 'GENERAL.AUTOCONNECT:yes' 'GENERAL.REASON:5 (IP configuration could not be reserved (no available address, timeout, etc.))' 'GENERAL.DRIVER:igc' 'WIRED-PROPERTIES.CARRIER:on' ;;
    *"connection show --active")
        case "$sc" in
            vpn) printf '%s\n' 'home:802-11-wireless:wlo1:activated' 'Work\: VPN:vpn:wlo1:activated' 'tailscale0:tun:tailscale0:activated' ;;
            *)   printf '%s\n' 'Café\: 5G:802-11-wireless:wlo1:activated' ;;
        esac ;;
esac
exit 0
EOF
cat >"$SB/bin/ip" <<'EOF'
#!/bin/sh
sc="${FAKE_NET:-waiting}"
case "$*" in
    "-j -4 route show default")
        case "$sc" in
            waiting) echo '[{"dst":"default","gateway":"192.168.1.1","dev":"wlo1","metric":600}]' ;;
            wiredup) echo '[{"dst":"default","dev":"wlo1","metric":600},{"dst":"default","dev":"enp3s0","metric":100}]' ;;
            vpn)     echo '[{"dst":"default","dev":"ppp0","metric":50},{"dst":"default","dev":"wlo1","metric":600}]' ;;
        esac ;;
    "-j -6 route show default") echo '[]' ;;
    "-j -4 route get 1.1.1.1")
        case "$sc" in
            waiting) echo '[{"dst":"1.1.1.1","dev":"wlo1"}]' ;;
            wiredup) echo '[{"dst":"1.1.1.1","dev":"enp3s0"}]' ;;
            vpn)     echo '[{"dst":"1.1.1.1","dev":"ppp0"}]' ;;
        esac ;;
    *) echo "RTNETLINK answers: Network is unreachable" >&2; exit 2 ;;
esac
EOF
cat >"$SB/bin/ethtool" <<'EOF'
#!/bin/sh
printf 'Settings for %s:\n' "$1"
printf '\tSupported ports: [ TP ]\n'
printf '\tSupported link modes:   10baseT/Half 10baseT/Full\n'
printf '\t                        100baseT/Half 100baseT/Full\n'
printf '\t                        1000baseT/Full\n'
printf '\t                        2500baseT/Full\n'
printf '\tSupported pause frame use: Symmetric\n'
printf '\tAdvertised link modes:  10baseT/Half 10baseT/Full\n'
printf '\t                        100baseT/Half 100baseT/Full\n'
printf '\tLink partner advertised link modes:  10baseT/Half 10baseT/Full\n'
printf '\t                                     100baseT/Half 100baseT/Full\n'
printf '\t                                     1000baseT/Full\n'
printf '\tSpeed: 100Mb/s\n'
printf '\tDuplex: Full\n'
EOF
chmod +x "$SB/bin/"*
for f in nmcli ip; do ln -s "$SB/bin/$f" "$SB/bin-noethtool/$f"; done

ns() { # ns <scenario> [PATH] → stdout; asserts JSON + exit 0
    local o rc
    o=$(FAKE_NET="$1" PATH="${2:-$SB/bin:$SB/sys}" "$PY" "$SCRIPT"); rc=$?
    [ "$rc" = 0 ] || echo "FAIL  [$1] exited $rc" >&2
    printf '%s' "$o"
}
q() { printf '%s' "$1" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); v=eval(sys.argv[1]); print(json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else v)' "$2"; }
want() { local got; got=$(q "$2" "$3"); [ "$got" = "$4" ] && ok "$1" || no "$1: $3 = $got, wanted $4"; }

o=$(ns waiting)
want "waiting: ok, connectivity" "$o" '[d["ok"], d["connectivity"]]' '[true, "full"]'
want "waiting: Wi-Fi carries traffic" "$o" '[d["primary"], d["uplink"]]' '[{"dev": "wlo1", "type": "wifi"}, {"dev": "wlo1", "type": "wifi"}]'
want "waiting: the cable is connecting, with link" "$o" '[d["wired"][0]["state"], d["wired"][0]["detail"], d["wired"][0]["carrier"]]' \
    '["connecting", "getting IP configuration", true]'
want "waiting: speed 100, NIC 2500, other end 1000" "$o" '[d["wired"][0]["speed"], d["wired"][0]["maxSpeed"], d["wired"][0]["partnerMax"]]' '[100, 2500, 1000]'
want "waiting: autoconnect + reason + driver" "$o" '[d["wired"][0]["autoconnect"], d["wired"][0]["reason"][:2], d["wired"][0]["driver"]]' '[true, "5 ", "igc"]'
want "nmcli escapes undone (Café: 5G)" "$o" 'd["wifi"]["connection"]' 'Café: 5G'
want "no VPN" "$o" 'd["vpns"]' '[]'

o=$(ns waiting "$SB/bin-noethtool:$SB/sys")
want "no ethtool → what the NIC can do is unknown" "$o" '[d["wired"][0]["speed"], d["wired"][0]["maxSpeed"]]' '[100, null]'

o=$(ns wiredup)
want "a cable that is the default route beats Wi-Fi" "$o" '[d["primary"]["type"], d["uplink"]]' '["ethernet", {"dev": "enp3s0", "type": "ethernet"}]'
want "device internet = the better of IPv4/IPv6" "$o" 'd["wired"][0]["internet"]' full
want "trailing spaces in a name survive" "$o" 'repr(d["wifi"]["connection"])' "'786  '"

o=$(ns vpn)
want "vpn: traffic leaves through ppp0, the uplink is still Wi-Fi" "$o" '[d["primary"]["dev"], d["uplink"]["dev"], d["connectivity"]]' '["ppp0", "wlo1", "limited"]'
want "vpn: the VPN (escaped name) carries traffic, Tailscale is marked" "$o" '[(v["name"], v["carriesTraffic"], v["tailscale"]) for v in d["vpns"]]' \
    '[["Work: VPN", true, false], ["tailscale0", false, true]]'

o=$(ns nmdown)
want "NetworkManager down → ok:false, still JSON" "$o" '[d["ok"], "NetworkManager" in d["error"]]' '[false, true]'

echo
[ "$fail" = 0 ] && echo "ewe-netstate-test: PASS" || echo "ewe-netstate-test: FAIL"
exit "$fail"
