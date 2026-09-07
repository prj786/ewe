#!/usr/bin/env python3
"""audio-ports.py — which audio nodes are attached to a port that isn't there.

WHY THIS EXISTS. A laptop's sound card publishes one PipeWire node per ALSA
UCM device, not per usable output: this machine has five sinks — Speaker,
Headphones, HDMI1, HDMI2, HDMI3 — of which three are dead, because no jack is
plugged and only one display carries audio. Every other desktop hides those,
and the control centre listed all five, which read as "the same device over
and over".

Availability is a property of the CARD's port, not of the node, and PipeWire
does not copy it onto the node — so it is not reachable from Quickshell's
Pipewire module at all. pactl knows, so ask pactl.

Output: one node name per line, each a node the UI should NOT offer. Silence
(and exit 0) when everything is available, pactl is missing, or the reply is
unparsable — an unreadable answer must never empty the device list.
"""
import json
import subprocess
import sys


def pactl(kind):
    out = subprocess.run(["pactl", "-f", "json", "list", kind],
                         capture_output=True, timeout=5)
    return json.loads(out.stdout or b"[]")


def main():
    try:
        cards = pactl("cards")
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0

    # "[Out] HDMI3" -> False.  pactl says "available", "not available" or
    # "availability unknown"; only an explicit "not available" is a no.
    # Unknown means the driver cannot tell (built-in speakers, USB), and
    # hiding those would empty the list on most desktops.
    dead = set()
    for c in cards:
        ports = c.get("ports") or {}
        if not isinstance(ports, dict):
            continue
        for name, p in ports.items():
            if isinstance(p, dict) and p.get("availability") == "not available":
                dead.add(name)
    if not dead:
        return 0

    for kind in ("sinks", "sources"):
        try:
            for node in pactl(kind):
                if node.get("active_port") in dead:
                    print(node.get("name", ""))
        except (OSError, ValueError, subprocess.SubprocessError):
            continue
    return 0


if __name__ == "__main__":
    sys.exit(main())
