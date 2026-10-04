#!/usr/bin/env bash
# ewe.sysmon — sample.sh tests: no compositor, no shell. Fixture /proc files
# stand in for the real ones (SYSMON_STAT / SYSMON_MEMINFO) so the CPU delta,
# the memory fraction, the clamps and the no-baseline case are exact; one
# last run reads the real /proc.
set -euo pipefail
cd "$(dirname "$0")"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
field() { python3 -c 'import json,sys; j=json.loads(sys.argv[1]); v=j
for k in sys.argv[2].split("."): v=v[k]
print(json.dumps(v))' "$1" "$2"; }

# cpu: user nice system idle iowait irq softirq steal → total 1000, idle 400
cat > "$SB/stat1" <<'EOF'
cpu  300 50 150 350 50 40 60 0 0 0
cpu0 300 50 150 350 50 40 60 0 0 0
intr 1 2 3
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
EOF

run() { SYSMON_STAT="$1" SYSMON_MEMINFO="$2" sh ./sample.sh "${@:3}"; }

out="$(run "$SB/stat1" "$SB/mem")"
check "exit 0 and ok"            "$(field "$out" ok)"    true
check "total jiffies"            "$(field "$out" total)" 1000
check "idle jiffies (idle+iowait)" "$(field "$out" idle)" 400
check "cpu is null without a baseline" "$(field "$out" cpu)" null
check "memory (16G total, 6G available)" "$(field "$out" mem)" 0.625

out="$(run "$SB/stat2" "$SB/mem" 1000 400)"
check "cpu delta: 700 busy of 1000" "$(field "$out" cpu)" 0.7
check "new total"                "$(field "$out" total)" 2000
check "new idle"                 "$(field "$out" idle)"  700

out="$(run "$SB/stat1" "$SB/mem" 1000 400)"
check "no time passed → cpu null (dt=0)" "$(field "$out" cpu)" null

out="$(run "$SB/stat1" "$SB/mem" 5000 100)"
check "counter went backwards → cpu null" "$(field "$out" cpu)" null

out="$(run "$SB/stat2" "$SB/mem" abc 400)"
check "garbage baseline → cpu null" "$(field "$out" cpu)" null

# idle jumped more than total (jiffy skew) → clamped at 0, never negative
printf 'cpu  800 50 350 1200 100 40 60 0 0 0\n' > "$SB/stat3"
out="$(run "$SB/stat3" "$SB/mem" 2000 700)"
check "clamp: idle > elapsed → 0.000" "$(field "$out" cpu)" 0.0

printf 'MemTotal: 1000 kB\nMemAvailable: 1200 kB\n' > "$SB/mem2"
out="$(run "$SB/stat1" "$SB/mem2")"
check "clamp: available > total → mem 0.000" "$(field "$out" mem)" 0.0

printf 'MemFree: 1 kB\n' > "$SB/mem3"
out="$(run "$SB/stat1" "$SB/mem3")"
check "no MemTotal → mem null, still ok" "$(field "$out" ok):$(field "$out" mem)" "true:null"

set +e
out="$(SYSMON_STAT="$SB/nope" SYSMON_MEMINFO="$SB/mem" sh ./sample.sh)"; rc=$?
set -e
check "unreadable stat → ok:false, exit 0" "$(field "$out" ok):$rc" "false:0"

# the real machine: one object, both fractions in range
out="$(sh ./sample.sh)"
check "real /proc → ok" "$(field "$out" ok)" true
python3 - "$out" <<'PY' || fails=$((fails + 1))
import json, sys
j = json.loads(sys.argv[1])
assert j["total"] > 0 and 0 <= j["idle"] <= j["total"], j
assert j["cpu"] is None, j
assert 0.0 <= j["mem"] <= 1.0, j
print("ok   real /proc values in range")
PY
out2="$(sh ./sample.sh "$(field "$out" total)" "$(field "$out" idle)")"
python3 - "$out2" <<'PY' || fails=$((fails + 1))
import json, sys
j = json.loads(sys.argv[1])
assert j["cpu"] is None or 0.0 <= j["cpu"] <= 1.0, j
print("ok   real /proc second tick cpu in range or null")
PY

[ "$fails" -eq 0 ] && echo "all tests passed" || { echo "$fails failure(s)"; exit 1; }
