#!/usr/bin/env bash
# X11 scale decision tests — no compositor, no real sysfs. Pulls the Python
# heredoc out of dotfiles/hypr/start-hyprland.sh and runs it against fake
# display profiles, fake DRM connector states and a fake lid. Covers the
# 0.24.1 bug (docked login read the undocked `lastKey` profile and sized X11
# apps for the 1.8x laptop on a 1x external) plus the cases around it.
set -euo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT

awk '/^_x11scale="\$\(python3/{f=1;next} /^PY$/{f=0} f' dotfiles/hypr/start-hyprland.sh > "$SB/x11.py"
[ -s "$SB/x11.py" ] || { echo "FAIL: x11 heredoc not found in start-hyprland.sh"; exit 1; }

python3 - "$SB/x11.py" <<'PY'
import builtins, glob, io, json, sys, tempfile
code = open(sys.argv[1]).read()
real_open, real_glob = builtins.open, glob.glob

def run(profiles, last, connected, lid="open"):
    p = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump({"version": 1, "lastKey": last, "profiles": profiles}, p); p.close()
    sysfs = {"/sys/class/drm/card0-%s/status" % n: ("connected" if n in connected else "disconnected")
             for n in ["eDP-1", "DP-1", "DP-2", "HDMI-A-1"]}
    def fglob(pat):
        if pat.startswith("/sys/class/drm"): return list(sysfs)
        if pat.startswith("/proc/acpi"): return ["/proc/acpi/button/lid/LID0/state"]
        return real_glob(pat)
    def fopen(path, *a, **k):
        if path in sysfs: return io.StringIO(sysfs[path] + "\n")
        if str(path).startswith("/proc/acpi"): return io.StringIO("state:      %s\n" % lid)
        return real_open(path, *a, **k)
    out, old = io.StringIO(), sys.stdout
    glob.glob, builtins.open, sys.stdout, sys.argv = fglob, fopen, out, ["x", p.name]
    try:
        exec(code, {"__name__": "__main__"})
    finally:
        glob.glob, builtins.open, sys.stdout = real_glob, real_open, old
    return out.getvalue().strip()

def lap(s=1.8, **k): return {**dict(name="eDP-1", scale=s, disabled=False, mirror="", primary=True), **k}
def ext(s=1, n="DP-1", **k): return {**dict(name=n, scale=s, disabled=False, mirror="", primary=False), **k}
P = {"lap": [lap()], "lap || sam": [lap(), ext()]}

cases = [
    ("docked, lastKey = undocked profile", run(P, "lap", {"eDP-1", "DP-1"}), ""),
    ("laptop alone, lastKey = docked",     run(P, "lap || sam", {"eDP-1"}), "1.80"),
    ("docked, lid shut",                   run(P, "lap", {"eDP-1", "DP-1"}, "closed"), ""),
    ("never-configured monitor on HDMI",   run(P, "lap", {"eDP-1", "HDMI-A-1"}), ""),
    ("2x external + 1.8x laptop",          run({"lap": [lap()], "k": [lap(), ext(2)]}, "lap", {"eDP-1", "DP-1"}), "1.80"),
    ("external saved as disabled",         run({"lap": [lap()], "k": [lap(), ext(disabled=True)]}, "lap", {"eDP-1", "DP-1"}), "1.80"),
    ("external mirroring the laptop",      run({"lap": [lap()], "k": [lap(), ext(mirror="eDP-1")]}, "lap", {"eDP-1", "DP-1"}), "1.80"),
    ("1x laptop alone",                    run({"lap": [lap(1)]}, "lap", {"eDP-1"}), ""),
    ("no saved profiles",                  run({}, "", {"eDP-1"}), ""),
]
fail = 0
for name, got, want in cases:
    if got != want:
        fail += 1
        print("FAIL: %s — got %r, want %r" % (name, got, want))
print("x11-scale: %d passed, %d failed" % (len(cases) - fail, fail))
sys.exit(1 if fail else 0)
PY
