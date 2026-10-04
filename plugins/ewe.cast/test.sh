#!/usr/bin/env bash
# ewe.cast plumbing tests — no compositor, no daemon, nothing on the host.
# Every command the two scripts call (systemctl, iw, pacman, vercmp,
# gst-inspect-1.0, gnome-network-displays, pactl, notify-send) is a fake on
# PATH, so the test covers: the manifest and QML files are consistent, the
# scripts parse, cast-check.sh's verdicts (fatal / degraded / ready) and
# cast-audio.sh's route-to-TV + restore-on-exit sequence.
set -euo pipefail
cd "$(dirname "$0")"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/run" "$SB/home"
export HOME="$SB/home" XDG_RUNTIME_DIR="$SB/run" LOG="$SB/calls.log"
: > "$LOG"

pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

# 1. static ------------------------------------------------------------------
for s in cast-check.sh cast-audio.sh; do
    check "$s parses (sh -n)" "sh -n $s"
done
check "test.sh parses (bash -n)" "bash -n test.sh"
check "manifest is JSON" "python3 -m json.tool manifest.json >/dev/null"
python3 - <<'PY' && pass=$((pass+1)) || { failn=$((failn+1)); echo "FAIL: manifest ↔ files"; }
import json, os, re, sys
m = json.load(open("manifest.json"))
assert m["id"] == "ewe.cast" and m["apiVersion"] == 3 and m["schemaVersion"] == 1
assert set(m["kinds"]) == {"service", "quick-tile", "quick-page", "bar-status"}
for k, f in m["entryPoints"].items():
    assert os.path.isfile(f), f
    src = open(f).read()
    assert "Globals." not in src, "%s reads the shell's Globals" % f      # public API only
    assert not re.search(r'#[0-9a-fA-F]{3,8}\b', src), "%s has a raw colour" % f   # Rule 8
assert m["quickPage"]["key"] == "cast" and "cast" in m["ipcAliases"]
for kb in m["keybinds"]:
    assert kb["ipc"].split()[0] in [m["id"]] + m["ipcAliases"], kb
# the singleton the four entry points share is listed in qmldir and imported nowhere else
assert "singleton CastState 1.0 CastState.qml" in open("qmldir").read()
assert open("CastState.qml").read().startswith("pragma Singleton")
# both IPC targets expose the same verbs
svc = open("Service.qml").read()
blocks = re.findall(r'IpcHandler \{\s*target: "([^"]+)"(.*?)\n    \}', svc, re.S)
verbs = {t: sorted(re.findall(r'function (\w+)\(', b)) for t, b in blocks}
assert set(verbs) == {"ewe.cast", "cast"} and verbs["ewe.cast"] == verbs["cast"] == ["legacy", "scan", "start", "stop", "toggle"], verbs
PY

# 2. fakes -------------------------------------------------------------------
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$LOG"\n%s\n' "$1" "$2" > "$SB/bin/$1"; chmod +x "$SB/bin/$1"; }
fake notify-send ':'
fake systemctl   'exit 3'                                   # nothing is active
fake iw          'case "$1" in list) echo "${IW_LIST:-}";; reg) echo "country ${IW_REG:-DE}: DFS-ETSI";; dev) echo "";; esac'
fake pacman      'echo "xdg-desktop-portal-hyprland ${XDPH:-1.4.1-2.1}"'
# pacman's vercmp semantics for what the script compares: pkgver-pkgrel, dotted numbers
fake vercmp      'python3 -c "
import sys
def key(v):
    ver, _, rel = v.partition(\"-\")
    return [tuple(int(x) for x in p.split(\".\") if x.isdigit()) for p in (ver, rel or \"0\")]
a, b = key(sys.argv[1]), key(sys.argv[2])
print(-1 if a < b else (0 if a == b else 1))" "$1" "$2"'
fake gst-inspect-1.0 'exit ${GST_RC:-0}'
export PATH="$SB/bin:$PATH"

# 3. cast-check.sh: fatal / degraded / ready --------------------------------
OUT="$SB/out"
run() { { sh ./cast-check.sh; echo "rc=$?"; } > "$OUT" 2>&1 || true; }
has() { grep -q -- "$1" "$OUT"; }
# the fatal case needs gnome-network-displays ABSENT — the host may have it, so
# the first run sees a PATH of symlinks to everything on PATH except that one
mkdir -p "$SB/nognd"
IFS_OLD="$IFS"; IFS=:
for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ "${f##*/}" = gnome-network-displays ] && continue
        [ -x "$f" ] && [ ! -e "$SB/nognd/${f##*/}" ] && ln -s "$f" "$SB/nognd/${f##*/}"
    done
done
IFS="$IFS_OLD"
PATH="$SB/nognd" run
check "no gnome-network-displays → exit 2 with the install hint" "has rc=2 && has 'paru -S gnome-network-displays'"
check "fatal verdict was toasted as critical" "grep -q 'notify-send .* -u critical' '$LOG'"

fake gnome-network-displays ':'
: > "$LOG"
IW_LIST="" run
check "NM down + no P2P + no avahi → exit 1" "has rc=1"
check "names NetworkManager" "has \"NetworkManager isn't running\""
check "names the missing Wi-Fi Direct" "has 'no Wi-Fi Direct'"
check "names avahi" "has avahi-daemon"
check "patched portal passes quietly" "! has FREEZE"

: > "$LOG"
XDPH=1.4.1-2 IW_LIST="* P2P-client" run
check "Arch's stock xdph 1.4.1-2 → the freeze warning" "has FREEZE && has 1.4.1-2.1"
XDPH=1.4.1-1.1 IW_LIST="* P2P-client" run
check "the older patched 1.4.1-1.1 → also flagged (below 1.4.1-2.1)" "has FREEZE"
GST_RC=1 IW_REG=00 IW_LIST="* P2P-GO" run
check "software encode + world regdom → quality hints" "has gst-plugin-va && has 'regulatory domain'"

fake systemctl 'exit 0'                                     # everything active
IW_LIST="* P2P-client" run
check "all good → exit 0 and 'cast: ready'" "has rc=0 && has 'cast: ready'"

# 4. cast-audio.sh: route to the TV sink, restore on exit --------------------
# a fake pactl with one GND sink, one playing stream; `subscribe` emits one
# event then ends, so the loop sees EOF and the EXIT trap restores
echo alsa_out > "$SB/default-sink"
cat > "$SB/bin/pactl" <<'PA'
#!/usr/bin/env bash
echo "pactl $*" >> "$LOG"
case "$1 ${2:-}" in
  "list short") case "$3" in
      sinks) printf '1\tgnome_network_displays_abc\tmodule-null-sink.c\n2\talsa_out\tmodule-alsa.c\n' ;;
      sink-inputs) printf '10\t2\t5\talsa_out\tPCM\n' ;;
    esac ;;
  "get-default-sink") cat "$SB/default-sink" ;;
  "set-default-sink") echo "$3" > "$SB/default-sink" ;;
  "move-sink-input") : ;;
  "subscribe") echo "Event 'new' on sink #1"; exit 0 ;;
esac
PA
sed -i "s|\$SB|$SB|g" "$SB/bin/pactl"; chmod +x "$SB/bin/pactl"
: > "$LOG"
timeout 10 sh ./cast-audio.sh || true
check "the GND sink became the default" "grep -q 'pactl set-default-sink gnome_network_displays_abc' '$LOG'"
check "the playing stream moved onto it" "grep -q 'pactl move-sink-input 10 gnome_network_displays_abc' '$LOG'"
check "audio toast sent" "grep -q 'notify-send .*Audio is playing on the TV' '$LOG'"
check "on exit the previous default came back" "[ \"\$(cat '$SB/default-sink')\" = alsa_out ]"
check "no fifo left behind" "! ls '$SB/run'/ewe-cast-audio.* >/dev/null 2>&1"

echo "ewe.cast: $pass passed, $failn failed"
[ "$failn" = 0 ]
