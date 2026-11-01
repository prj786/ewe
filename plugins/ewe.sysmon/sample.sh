#!/bin/sh
# ewe.sysmon — one sample of CPU, memory and internet speed, as JSON, in one
# process.
#
#   sample.sh [prevTotal prevIdle [prevIf prevRx prevTx prevT]]
#
# Everything is read with the shell's own `read` — no awk, no grep, no date —
# so a tick costs exactly one fork. Prints one line:
#
#   {"ok":true,"total":T,"idle":I,"cpu":0.123,"cores":8,
#    "mem":0.456,"memTotal":KB,"memUsed":KB,"swapTotal":KB,"swapUsed":KB,
#    "net":{"if":"wlo1","kind":"wifi","rx":B,"tx":B,"t":CS,"down":B/s,"up":B/s}}
#
# CPU: `total`/`idle` are the raw jiffies to hand back next time; `cpu` is the
# busy fraction over that interval and `null` without a usable baseline
# (first tick, or no jiffies passed); `cores` counts the cpuN lines.
# Memory: `mem` is (MemTotal - MemAvailable) / MemTotal; the four sizes are kB.
# Fractions are clamped to 0..1.
#
# Internet: `net` is the interface of the default route — the lowest-metric
# up route to 0.0.0.0/0 in /proc/net/route — or null when there is none
# (offline). `rx`/`tx` are its byte counters (/proc/net/dev) and `t` the
# uptime in centiseconds (/proc/uptime), all three to hand back next time.
# `down`/`up` are bytes per second over the real time since the previous
# sample, and null when there is nothing to compare with: the first sample,
# a different interface than last time, a counter that went backwards (the
# interface was re-created), or no time passed. `kind` is "wifi" (the
# interface has /sys/class/net/<if>/wireless or phy80211), "vpn" (a tunnel or
# point-to-point link: ARPHRD type 512 ppp, 65534 none, 776 sit, 778 gre) or
# "ethernet".
#
# Always exits 0 and always prints one JSON object — an unreadable /proc/stat
# or /proc/meminfo is {"ok":false,"error":"..."}; missing network files only
# make `net` null. The tests point these at fixtures:
#   SYSMON_STAT SYSMON_MEMINFO SYSMON_ROUTE SYSMON_NETDEV SYSMON_UPTIME
#   SYSMON_SYSNET (the /sys/class/net directory)
stat="${SYSMON_STAT:-/proc/stat}"
meminfo="${SYSMON_MEMINFO:-/proc/meminfo}"
route="${SYSMON_ROUTE:-/proc/net/route}"
netdev="${SYSMON_NETDEV:-/proc/net/dev}"
uptime="${SYSMON_UPTIME:-/proc/uptime}"
sysnet="${SYSMON_SYSNET:-/sys/class/net}"
prev_total="${1:-}"
prev_idle="${2:-}"
prev_if="${3:-}"
prev_rx="${4:-}"
prev_tx="${5:-}"
prev_t="${6:-}"

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }
# a non-negative decimal integer (no sign, no hex, no leading garbage)
isnum() { case "$1" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# ── CPU: cpu  user nice system idle iowait irq softirq steal guest guest_nice
#    then one cpuN line per core
[ -r "$stat" ] || fail "cannot read $stat"
cores=0
{
    read -r _cpu u n s i w q sq st _rest || fail "cannot read $stat"
    while read -r key _r; do
        case "$key" in
            cpu[0-9]*) cores=$((cores + 1)) ;;
            *) break ;;
        esac
    done
} < "$stat"
[ "$_cpu" = "cpu" ] || fail "no cpu line in $stat"
# guest/guest_nice are already folded into user/nice by the kernel; the
# first eight fields are the whole budget
total=$(( ${u:-0} + ${n:-0} + ${s:-0} + ${i:-0} + ${w:-0} + ${q:-0} + ${sq:-0} + ${st:-0} ))
idle=$(( ${i:-0} + ${w:-0} ))

cpu=null
if isnum "$prev_total" && isnum "$prev_idle"; then
    dt=$(( total - prev_total ))
    di=$(( idle - prev_idle ))
    if [ "$dt" -gt 0 ]; then
        busy=$(( (dt - di) * 1000 / dt ))
        [ "$busy" -lt 0 ] && busy=0
        [ "$busy" -gt 1000 ] && busy=1000
        cpu=$(printf '%d.%03d' $(( busy / 1000 )) $(( busy % 1000 )))
    fi
fi

# ── memory (the loop's own status must not decide anything: a file without
#    a key simply leaves it at 0)
[ -r "$meminfo" ] || fail "cannot read $meminfo"
mt=0; ma=0; swt=0; swf=0; seen=0
while read -r key val _unit; do
    case "$key" in
        MemTotal:)     mt=$val;  seen=$((seen + 1)) ;;
        MemAvailable:) ma=$val;  seen=$((seen + 1)) ;;
        SwapTotal:)    swt=$val; seen=$((seen + 1)) ;;
        SwapFree:)     swf=$val; seen=$((seen + 1)) ;;
    esac
    [ "$seen" -ge 4 ] && break
done < "$meminfo"
isnum "$mt" || mt=0; isnum "$ma" || ma=0; isnum "$swt" || swt=0; isnum "$swf" || swf=0
mem=null
mused=0
if [ "$mt" -gt 0 ]; then
    mused=$(( mt - ma ))
    [ "$mused" -lt 0 ] && mused=0
    used=$(( mused * 1000 / mt ))
    [ "$used" -gt 1000 ] && { used=1000; mused=$mt; }
    mem=$(printf '%d.%03d' $(( used / 1000 )) $(( used % 1000 )))
fi
swused=$(( swt - swf ))
[ "$swused" -lt 0 ] && swused=0

# ── internet: the default route's interface, its counters, the clock
net=null
ifc=""
if [ -r "$route" ]; then
    best=""
    while read -r r_if r_dst _gw r_flags _ref _use r_metric r_mask _rest; do
        [ "$r_dst" = "00000000" ] && [ "$r_mask" = "00000000" ] || continue
        case "$r_flags" in ""|*[!0-9A-Fa-f]*) continue ;; esac
        [ $(( 0x$r_flags & 1 )) -eq 1 ] || continue        # RTF_UP
        isnum "$r_metric" || continue
        if [ -z "$best" ] || [ "$r_metric" -lt "$best" ]; then
            best=$r_metric; ifc=$r_if
        fi
    done < "$route"
fi

rx=""; tx=""
if [ -n "$ifc" ] && [ -r "$netdev" ]; then
    # "  wlo1: 1299283674 1561251 0 …" — the name is right-aligned and a long
    # one or a big counter can leave no space around the colon
    while IFS= read -r line; do
        case "$line" in *:*) ;; *) continue ;; esac
        name=${line%%:*}
        name=${name##* }
        [ "$name" = "$ifc" ] || continue
        # shellcheck disable=SC2086 # the counters are split on purpose
        set -- ${line#*:}
        rx=${1:-}; tx=${9:-}
        break
    done < "$netdev"
fi

t=""
if [ -r "$uptime" ]; then
    up=""
    read -r up _idle < "$uptime"
    case "$up" in
        *.??) t="${up%.*}${up#*.}" ;;               # 39181.55 → 3918155 cs
        *.?)  t="${up%.*}${up#*.}0" ;;
        *)    isnum "$up" && t="${up}00" ;;
    esac
    t=${t#"${t%%[!0]*}"}                            # no leading zero: sh reads 08 as octal
    [ -n "$t" ] || { isnum "${up%.*}" && t=0; }
fi

if [ -n "$ifc" ] && isnum "$rx" && isnum "$tx" && isnum "$t"; then
    kind=ethernet
    if [ -d "$sysnet/$ifc/wireless" ] || [ -e "$sysnet/$ifc/phy80211" ]; then
        kind=wifi
    elif [ -r "$sysnet/$ifc/type" ]; then
        htype=""
        read -r htype < "$sysnet/$ifc/type"
        case "$htype" in 512|65534|776|778) kind=vpn ;; esac
    fi
    # the interface name goes into JSON (and comes back as prevIf): keep only
    # what an interface name may hold
    ifj=$ifc
    case "$ifj" in *[!A-Za-z0-9._@-]*) ifj=$(printf '%s' "$ifj" | tr -cd 'A-Za-z0-9._@-') ;; esac
    down=null; upr=null
    if [ "$prev_if" = "$ifj" ] && isnum "$prev_rx" && isnum "$prev_tx" && isnum "$prev_t"; then
        dts=$(( t - prev_t ))
        if [ "$dts" -gt 0 ] && [ "$rx" -ge "$prev_rx" ] && [ "$tx" -ge "$prev_tx" ]; then
            down=$(( (rx - prev_rx) * 100 / dts ))
            upr=$(( (tx - prev_tx) * 100 / dts ))
        fi
    fi
    net=$(printf '{"if":"%s","kind":"%s","rx":%s,"tx":%s,"t":%s,"down":%s,"up":%s}' \
        "$ifj" "$kind" "$rx" "$tx" "$t" "$down" "$upr")
fi

printf '{"ok":true,"total":%d,"idle":%d,"cpu":%s,"cores":%d,"mem":%s,"memTotal":%d,"memUsed":%d,"swapTotal":%d,"swapUsed":%d,"net":%s}\n' \
    "$total" "$idle" "$cpu" "$cores" "$mem" "$mt" "$mused" "$swt" "$swused" "$net"
exit 0
