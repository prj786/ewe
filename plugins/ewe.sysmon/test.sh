#!/usr/bin/env bash
# ewe.sysmon — sample.sh tests: no compositor, no shell. Fixture /proc and
# /sys files stand in for the real ones (SYSMON_STAT, SYSMON_MEMINFO,
# SYSMON_ROUTE, SYSMON_NETDEV, SYSMON_UPTIME, SYSMON_SYSNET) so the CPU delta,
# the memory sizes, the default route, the speed over real elapsed time and
# every "no rate" case are exact; one last run reads the real machine.
set -euo pipefail
cd "$(dirname "$0")"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
field() { python3 -c 'import json,sys; j=json.loads(sys.argv[1]); v=j
for k in sys.argv[2].split("."): v=v[k] if v is not None else None
print(json.dumps(v))' "$1" "$2"; }

# cpu: user nice system idle iowait irq softirq steal → total 1000, idle 400;
# four cores
cat > "$SB/stat1" <<'EOF'
cpu  300 50 150 350 50 40 60 0 0 0
cpu0 75 12 37 87 12 10 15 0 0 0
cpu1 75 12 37 87 12 10 15 0 0 0
cpu2 75 13 38 88 13 10 15 0 0 0
cpu3 75 13 38 88 13 10 15 0 0 0
intr 1 2 3
ctxt 99
EOF
# +1000 jiffies later: 700 busy, 300 idle → cpu 0.700
cat > "$SB/stat2" <<'EOF'
cpu  800 50 350 600 100 40 60 0 0 0
EOF
cat > "$SB/mem" <<'EOF'
MemTotal:       16000000 kB
MemFree:         2000000 kB
MemAvailable:    6000000 kB
Buffers:          100000 kB
SwapCached:            0 kB
SwapTotal:       8000000 kB
SwapFree:        7500000 kB
EOF

# the network: wlo1 is the default route (metric 600) beside a cable at
# metric 100 that is DOWN (flags 0002: gateway, not up) and a link route
cat > "$SB/route" <<'EOF'
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
enp1s0	00000000	0101A8C0	0002	0	0	100	00000000	0	0	0
wlo1	00000000	0101A8C0	0003	0	0	600	00000000	0	0	0
wlo1	0001A8C0	00000000	0001	0	0	600	00FFFFFF	0	0	0
EOF
# the same plus the cable up at metric 100: the cable wins
cat > "$SB/route-cable" <<'EOF'
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
wlo1	00000000	0101A8C0	0003	0	0	600	00000000	0	0	0
enp1s0	00000000	0101A8C0	0003	0	0	100	00000000	0	0	0
EOF
# a link route only, no default: offline
cat > "$SB/route-none" <<'EOF'
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
wlo1	0001A8C0	00000000	0001	0	0	600	00FFFFFF	0	0	0
EOF
# the L2TP VPN: ppp0 carries the default route
cat > "$SB/route-ppp" <<'EOF'
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
ppp0	00000000	00000000	0001	0	0	0	00000000	0	0	0
wlo1	00000000	0101A8C0	0003	0	0	600	00000000	0	0	0
EOF
netdev() {   # rx tx for wlo1, rx tx for enp1s0 → a /proc/net/dev; a long
             # interface name leaves no space before its counters
    cat <<EOF
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 5000 50 0 0 0 0 0 0 5000 50 0 0 0 0 0 0
  wlo1: $1 900 0 0 0 0 0 0 $2 700 0 0 0 0 0 0
enp1s0:$3 10 0 0 0 0 0 0 $4 10 0 0 0 0 0 0
  ppp0: 70000 5 0 0 0 0 0 0 30000 5 0 0 0 0 0 0
EOF
}
netdev 1000000 200000 123456789012 5 > "$SB/dev1"
# 2.00 s later: +2,400,000 down, +172,000 up → 1,200,000 and 86,000 B/s
netdev 3400000 372000 123456789012 5 > "$SB/dev2"
# the counters went backwards (the interface was re-created)
netdev 500 100 123456789012 5 > "$SB/dev-reset"
printf '1000.00 7000.00\n' > "$SB/up1"
printf '1002.00 7010.00\n' > "$SB/up2"
printf '0.08 0.01\n'       > "$SB/up-early"     # 08 must not be read as octal
mkdir -p "$SB/sys/wlo1/wireless" "$SB/sys/enp1s0" "$SB/sys/ppp0"
echo 1   > "$SB/sys/wlo1/type"
echo 1   > "$SB/sys/enp1s0/type"
echo 512 > "$SB/sys/ppp0/type"

# run STAT MEM ROUTE NETDEV UPTIME [args…]
run() {
    SYSMON_STAT="$1" SYSMON_MEMINFO="$2" SYSMON_ROUTE="$3" SYSMON_NETDEV="$4" SYSMON_UPTIME="$5" \
        SYSMON_SYSNET="$SB/sys" sh ./sample.sh "${@:6}"
}
std() { run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev1" "$SB/up1" "$@"; }

# ── CPU + memory ─────────────────────────────────────────────────────────────
out="$(std)"
check "exit 0 and ok"            "$(field "$out" ok)"    true
check "total jiffies"            "$(field "$out" total)" 1000
check "idle jiffies (idle+iowait)" "$(field "$out" idle)" 400
check "cpu is null without a baseline" "$(field "$out" cpu)" null
check "cores: four cpuN lines"   "$(field "$out" cores)" 4
check "memory (16G total, 6G available)" "$(field "$out" mem)" 0.625
check "memory total kB"          "$(field "$out" memTotal)" 16000000
check "memory used kB"           "$(field "$out" memUsed)" 10000000
check "swap total kB"            "$(field "$out" swapTotal)" 8000000
check "swap used kB"             "$(field "$out" swapUsed)" 500000

out="$(run "$SB/stat2" "$SB/mem" "$SB/route" "$SB/dev1" "$SB/up1" 1000 400)"
check "cpu delta: 700 busy of 1000" "$(field "$out" cpu)" 0.7
check "new total"                "$(field "$out" total)" 2000
check "new idle"                 "$(field "$out" idle)"  700
check "cores: a /proc/stat without cpuN lines" "$(field "$out" cores)" 0

out="$(std 1000 400)"
check "no time passed → cpu null (dt=0)" "$(field "$out" cpu)" null

out="$(std 5000 100)"
check "counter went backwards → cpu null" "$(field "$out" cpu)" null

out="$(run "$SB/stat2" "$SB/mem" "$SB/route" "$SB/dev1" "$SB/up1" abc 400)"
check "garbage baseline → cpu null" "$(field "$out" cpu)" null

# idle jumped more than total (jiffy skew) → clamped at 0, never negative
printf 'cpu  800 50 350 1200 100 40 60 0 0 0\n' > "$SB/stat3"
out="$(run "$SB/stat3" "$SB/mem" "$SB/route" "$SB/dev1" "$SB/up1" 2000 700)"
check "clamp: idle > elapsed → 0.000" "$(field "$out" cpu)" 0.0

printf 'MemTotal: 1000 kB\nMemAvailable: 1200 kB\n' > "$SB/mem2"
out="$(run "$SB/stat1" "$SB/mem2" "$SB/route" "$SB/dev1" "$SB/up1")"
check "clamp: available > total → mem 0.000, used 0" "$(field "$out" mem):$(field "$out" memUsed)" "0.0:0"
check "no swap lines → swap 0" "$(field "$out" swapTotal):$(field "$out" swapUsed)" "0:0"

printf 'MemFree: 1 kB\n' > "$SB/mem3"
out="$(run "$SB/stat1" "$SB/mem3" "$SB/route" "$SB/dev1" "$SB/up1")"
check "no MemTotal → mem null, still ok" "$(field "$out" ok):$(field "$out" mem)" "true:null"

set +e
out="$(SYSMON_STAT="$SB/nope" SYSMON_MEMINFO="$SB/mem" sh ./sample.sh)"; rc=$?
set -e
check "unreadable stat → ok:false, exit 0" "$(field "$out" ok):$rc" "false:0"

# ── internet ─────────────────────────────────────────────────────────────────
out="$(std)"
check "default route: the UP one (wlo1), not the lower-metric DOWN cable" "$(field "$out" net.if)" '"wlo1"'
check "wlo1 has wireless/ → kind wifi" "$(field "$out" net.kind)" '"wifi"'
check "counters of the route's interface" "$(field "$out" net.rx):$(field "$out" net.tx)" "1000000:200000"
check "clock in centiseconds"    "$(field "$out" net.t)" 100000
check "first sample: no rate (no baseline)" "$(field "$out" net.down):$(field "$out" net.up)" "null:null"

out="$(run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev2" "$SB/up2" 1000 400 wlo1 1000000 200000 100000)"
check "rate: 2.4 MB down over 2.00 s → 1200000 B/s" "$(field "$out" net.down)" 1200000
check "rate: 172 kB up over 2.00 s → 86000 B/s" "$(field "$out" net.up)" 86000
check "the new counters are the next baseline" "$(field "$out" net.rx):$(field "$out" net.t)" "3400000:100200"

out="$(run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev2" "$SB/up1" 1000 400 wlo1 1000000 200000 100000)"
check "no time passed → no rate" "$(field "$out" net.down)" null

out="$(run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev-reset" "$SB/up2" 1000 400 wlo1 1000000 200000 100000)"
check "counter reset (went backwards) → no rate" "$(field "$out" net.down):$(field "$out" net.up)" "null:null"
check "counter reset: the new counters still come back" "$(field "$out" net.rx)" 500

out="$(run "$SB/stat1" "$SB/mem" "$SB/route-cable" "$SB/dev2" "$SB/up2" 1000 400 wlo1 1000000 200000 100000)"
check "lowest metric wins: the cable (metric 100)" "$(field "$out" net.if)" '"enp1s0"'
check "cable without wireless/ → kind ethernet" "$(field "$out" net.kind)" '"ethernet"'
check "a long counter glued to the colon is read" "$(field "$out" net.rx)" 123456789012
check "interface changed (wlo1 → enp1s0) → no rate" "$(field "$out" net.down)" null

out="$(run "$SB/stat1" "$SB/mem" "$SB/route-ppp" "$SB/dev1" "$SB/up1")"
check "a VPN that takes the default route (ppp0, type 512) → kind vpn" "$(field "$out" net.if):$(field "$out" net.kind)" '"ppp0":"vpn"'

out="$(run "$SB/stat1" "$SB/mem" "$SB/route-none" "$SB/dev1" "$SB/up1")"
check "no default route → net null (offline), still ok" "$(field "$out" ok):$(field "$out" net)" "true:null"

out="$(run "$SB/stat1" "$SB/mem" "$SB/nope" "$SB/dev1" "$SB/up1")"
check "unreadable route table → net null" "$(field "$out" net)" null

printf 'Inter-|\n face |\n    lo: 1 1 0 0 0 0 0 0 1 1 0 0 0 0 0 0\n' > "$SB/dev-missing"
out="$(run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev-missing" "$SB/up1")"
check "route's interface missing from /proc/net/dev → net null" "$(field "$out" net)" null

out="$(run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev1" "$SB/up-early")"
check "uptime 0.08 s → 8 cs (no octal)" "$(field "$out" net.t)" 8

out="$(run "$SB/stat1" "$SB/mem" "$SB/route" "$SB/dev2" "$SB/up2" 1000 400 wlo1 x 200000 100000)"
check "garbage network baseline → no rate" "$(field "$out" net.down)" null

# ── the real machine: one object, everything in range ───────────────────────
out="$(sh ./sample.sh)"
check "real /proc → ok" "$(field "$out" ok)" true
python3 - "$out" <<'PY' || fails=$((fails + 1))
import json, sys
j = json.loads(sys.argv[1])
assert j["total"] > 0 and 0 <= j["idle"] <= j["total"], j
assert j["cpu"] is None, j
assert j["cores"] >= 1, j
assert 0.0 <= j["mem"] <= 1.0 and 0 < j["memUsed"] <= j["memTotal"], j
assert 0 <= j["swapUsed"] <= max(j["swapTotal"], 0), j
n = j["net"]
assert n is None or (n["kind"] in ("wifi", "ethernet", "vpn") and n["down"] is None and n["rx"] >= 0), j
print("ok   real /proc values in range (net: %s)" % (n and n["if"] + "/" + n["kind"]))
PY
n_args() { python3 -c 'import json,sys; j=json.loads(sys.argv[1]); n=j["net"] or {}
print(" ".join(str(x) for x in [j["total"], j["idle"]] + ([n["if"], n["rx"], n["tx"], n["t"]] if n else [])))' "$1"; }
sleep 0.2
# shellcheck disable=SC2046 # the baseline is split on purpose
out2="$(sh ./sample.sh $(n_args "$out"))"
python3 - "$out2" <<'PY' || fails=$((fails + 1))
import json, sys
j = json.loads(sys.argv[1])
assert j["cpu"] is None or 0.0 <= j["cpu"] <= 1.0, j
n = j["net"]
assert n is None or n["down"] is None or (n["down"] >= 0 and n["up"] >= 0), j
print("ok   real second tick: cpu in range or null, speed >= 0 or null")
PY

[ "$fails" -eq 0 ] && echo "all tests passed" || { echo "$fails failure(s)"; exit 1; }
