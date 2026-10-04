#!/bin/sh
# ewe.sysmon — one sample of CPU and memory, as JSON, in one process.
#
#   sample.sh [prevTotal prevIdle]
#
# Reads the first line of /proc/stat and MemTotal/MemAvailable from
# /proc/meminfo with the shell's own `read` — no awk, no grep, so a tick
# costs exactly one fork (the sampler used to spawn three). Prints
#
#   {"ok":true,"total":T,"idle":I,"cpu":0.123,"mem":0.456}
#
# `total`/`idle` are the raw jiffies to hand back next time; `cpu` is the
# busy fraction over that interval and `null` without a usable baseline
# (first tick, or no jiffies passed); `mem` is (MemTotal - MemAvailable) /
# MemTotal. Both fractions are clamped to 0..1. Always exits 0 and always
# prints one JSON object — a read error is {"ok":false,"error":"..."}.
# SYSMON_STAT / SYSMON_MEMINFO point at other files (the tests).
stat="${SYSMON_STAT:-/proc/stat}"
meminfo="${SYSMON_MEMINFO:-/proc/meminfo}"
prev_total="${1:-}"
prev_idle="${2:-}"

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

# ── CPU: cpu  user nice system idle iowait irq softirq steal guest guest_nice
[ -r "$stat" ] || fail "cannot read $stat"
read -r _cpu u n s i w q sq st _rest < "$stat" || fail "cannot read $stat"
[ "$_cpu" = "cpu" ] || fail "no cpu line in $stat"
# guest/guest_nice are already folded into user/nice by the kernel; the
# first eight fields are the whole budget
total=$(( ${u:-0} + ${n:-0} + ${s:-0} + ${i:-0} + ${w:-0} + ${q:-0} + ${sq:-0} + ${st:-0} ))
idle=$(( ${i:-0} + ${w:-0} ))

cpu=null
case "$prev_total$prev_idle" in
    *[!0-9]*|"") ;;                       # no (or garbage) baseline → null
    *)
        dt=$(( total - prev_total ))
        di=$(( idle - prev_idle ))
        if [ "$dt" -gt 0 ]; then
            busy=$(( (dt - di) * 1000 / dt ))
            [ "$busy" -lt 0 ] && busy=0
            [ "$busy" -gt 1000 ] && busy=1000
            cpu=$(printf '%d.%03d' $(( busy / 1000 )) $(( busy % 1000 )))
        fi ;;
esac

# ── memory (the loop's own status must not decide anything: a file without
#    both keys simply leaves mt/ma at 0)
[ -r "$meminfo" ] || fail "cannot read $meminfo"
mt=0; ma=0
while read -r key val _unit; do
    case "$key" in
        MemTotal:)     mt=$val ;;
        MemAvailable:) ma=$val ;;
    esac
    if [ "$mt" -gt 0 ] && [ "$ma" -gt 0 ]; then break; fi
done < "$meminfo"
mem=null
if [ "$mt" -gt 0 ]; then
    used=$(( (mt - ma) * 1000 / mt ))
    [ "$used" -lt 0 ] && used=0
    [ "$used" -gt 1000 ] && used=1000
    mem=$(printf '%d.%03d' $(( used / 1000 )) $(( used % 1000 )))
fi

printf '{"ok":true,"total":%d,"idle":%d,"cpu":%s,"mem":%s}\n' "$total" "$idle" "$cpu" "$mem"
exit 0
