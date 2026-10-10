#!/usr/bin/env bash
# ewe.dock checks — no compositor. 1) the manifest validates with ewe's own
# tool (a sibling ewe checkout, or EWE_PLUGIN_TOOL), in a throwaway HOME so
# nothing of the real account is read or written; 2) Rule 8: no raw colour,
# size or duration in the QML — every figure is a Theme token; 3) the compat
# contracts other parts of ewe match by name: the layer namespaces, the IPC
# targets, the inset id.
set -euo pipefail
cd "$(dirname "$0")"

TOOL="${EWE_PLUGIN_TOOL:-$(dirname "$PWD")/ewe/bin/ewe-plugin}"
fail=0
ok()   { echo "ok   $*"; }
bad()  { echo "FAIL $*"; fail=1; }

# 1 — manifest -----------------------------------------------------------------
if [ -x "$TOOL" ]; then
  SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
  mkdir -p "$SB/cfg/ewe" "$SB/payload"
  if HOME="$SB" XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" \
     XDG_CACHE_HOME="$SB/cache" EWE_PAYLOAD_PLUGINS="$SB/payload" \
     "$TOOL" validate . --first-party >/dev/null; then ok "manifest validates (--first-party)"; else bad "manifest does not validate"; fi
else
  echo "skip manifest validation: no ewe-plugin at $TOOL (set EWE_PLUGIN_TOOL)"
fi
python3 - <<'PY' || fail=1
import json
m = json.load(open("manifest.json"))
assert m["id"] == "ewe.dock" and m["apiVersion"] == 3 and m["kinds"] == ["panel"], m
assert m["ipcAliases"] == ["launcher"], m["ipcAliases"]
assert m["entryPoints"]["panel"] == "Dock.qml"
# the settings live here since 1.1.0, carried over from [desktop.dock]
s = {o["key"]: o for o in m["settings"]}
assert set(s) == {"autohide", "icon_size"}, set(s)
assert s["autohide"]["legacy"] == "desktop.dock.autohide" and s["icon_size"]["legacy"] == "desktop.dock.icon_size"
assert s["icon_size"]["choices"] == ["small", "normal", "large"]
print("ok   manifest fields + settings")
PY
grep -q 'property var settings' Dock.qml && grep -q 'root.settings.autohide' Dock.qml && grep -q 'root.settings.icon_size' Dock.qml \
  && ok "Dock.qml reads its own settings" || bad "Dock.qml does not read its settings"

# 2 — Rule 8 -------------------------------------------------------------------
# a hex colour, a named colour other than "transparent", a duration or a pixel
# figure that is not a Theme token (bare integers are allowed only where they
# are counts, indices, factors or the 0/1 of a flag)
if grep -nE '"#[0-9a-fA-F]{3,8}"|Qt\.rgba\(|"(white|black|red|grey|gray)"' Dock.qml PinnedApps.qml; then bad "raw colour"; else ok "no raw colour"; fi
if grep -nE 'duration: *[0-9]|interval: *[0-9]|pixelSize: *[0-9]|(width|height|radius|margin[A-Za-z]*|spacing|x|y): *[0-9]{2,}' Dock.qml PinnedApps.qml; then bad "raw size/duration"; else ok "no raw size or duration"; fi

# 3 — compat contracts ---------------------------------------------------------
grep -q 'WlrLayershell.namespace: "quickshell:dock"' Dock.qml        && ok "namespace quickshell:dock"     || bad "namespace quickshell:dock"
grep -q 'WlrLayershell.namespace: "quickshell:launcher"' PinnedApps.qml && ok "namespace quickshell:launcher" || bad "namespace quickshell:launcher"
grep -q 'target: "launcher"' Dock.qml  && ok "IPC alias launcher"  || bad "IPC alias launcher"
grep -q 'target: "ewe.dock"' Dock.qml  && ok "IPC target ewe.dock" || bad "IPC target ewe.dock"
grep -q 'Shell.setBottomInset(root.pluginId, 0, false)' Dock.qml && ok "inset withdrawn on destruction" || bad "inset withdrawn on destruction"
grep -q 'overviewCover\|Shell.overviewOpen' Dock.qml && ok "Overview slide from Shell" || bad "Overview slide from Shell"
[ -f assets/ewe-mark.svg ] && ok "the ewe mark" || bad "assets/ewe-mark.svg missing"

[ "$fail" = 0 ] && echo "all good" || { echo "problems"; exit 1; }
