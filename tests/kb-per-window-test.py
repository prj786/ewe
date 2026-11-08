#!/usr/bin/env python3
"""kb-per-window.py against a FAKE Hyprland (both sockets are ours) — never the
live session. Checks: no process is spawned per event, one `switchxkblayout all`
per real change, nothing when the layout already matches, per-window memory,
reload re-reads the layout list. Run: python3 tests/kb-per-window-test.py"""

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "dotfiles/hypr/scripts/kb-per-window.py")

tmp = tempfile.mkdtemp(prefix="kbpw-")
sig = "fake"
hdir = os.path.join(tmp, "hypr", sig)
os.makedirs(hdir)
req_path = os.path.join(hdir, ".socket.sock")
ev_path = os.path.join(hdir, ".socket2.sock")

requests = []
state = {"layout": "us,ge", "keymap": "English (US)"}


def serve_requests():
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(req_path)
    srv.listen(8)
    while True:
        c, _ = srv.accept()
        req = c.recv(65536).decode()
        requests.append(req)
        if req == "j/getoption input:kb_layout":
            out = json.dumps({"option": "input:kb_layout", "str": state["layout"], "set": True})
        elif req == "j/devices":
            out = json.dumps({"keyboards": [
                {"name": "power-button", "active_keymap": state["keymap"], "main": False},
                {"name": "kbd", "active_keymap": state["keymap"], "main": True},
            ]})
        else:
            out = "ok"
        c.sendall(out.encode())
        c.close()


ev_srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
ev_srv.bind(ev_path)
ev_srv.listen(1)
threading.Thread(target=serve_requests, daemon=True).start()

# hyprctl on PATH that records a call — must never run
bindir = os.path.join(tmp, "bin")
os.makedirs(bindir)
spawned = os.path.join(tmp, "hyprctl-called")
with open(os.path.join(bindir, "hyprctl"), "w") as f:
    f.write(f"#!/bin/sh\necho \"$@\" >> {spawned}\n")
os.chmod(os.path.join(bindir, "hyprctl"), 0o755)

env = dict(os.environ, XDG_RUNTIME_DIR=tmp, HYPRLAND_INSTANCE_SIGNATURE=sig,
           PATH=bindir + ":" + os.environ.get("PATH", ""))
proc = subprocess.Popen([sys.executable, "-I", SCRIPT], env=env)
ev, _ = ev_srv.accept()


def send(*events, wait=0.3):
    ev.sendall(("".join(e + "\n" for e in events)).encode())
    time.sleep(wait)


def switches():
    return [r for r in requests if r.startswith("switchxkblayout")]


fails = 0


def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    fails += 0 if cond else 1


time.sleep(0.3)
send("activewindowv2>>aaa")
check("focus a new window already on layout 0 -> no switch", switches() == [])

send("activelayout>>kbd,Georgian")
check("manual switch is recorded, not echoed", switches() == [])

send("activewindowv2>>bbb")
check("focus another window -> one switch to 0 for all keyboards",
      switches() == ["switchxkblayout all 0"])

send("activelayout>>kbd,English (US)", "activelayout>>power-button,English (US)")
send("activewindowv2>>aaa")
check("back to the Georgian window -> switch all to 1",
      switches()[-1] == "switchxkblayout all 1" and len(switches()) == 2)

send("activelayout>>kbd,Georgian")
send("activewindowv2>>aaa")
check("refocus the same window on the same layout -> nothing", len(switches()) == 2)

send("closewindow>>aaa", "activewindowv2>>aaa")
check("closed window forgets its layout -> back to 0", switches()[-1] == "switchxkblayout all 0")

state["layout"] = "us"
send("configreloaded>>")
n = len(switches())
send("activelayout>>kbd,English (US)", "activewindowv2>>ccc", "activewindowv2>>bbb")
check("one layout after reload -> never switch", len(switches()) == n)

check("no hyprctl process spawned", not os.path.exists(spawned))

proc.terminate()
proc.wait(timeout=5)
shutil.rmtree(tmp, ignore_errors=True)
print(f"{'PASS' if not fails else 'FAIL'}: kb-per-window ({fails} failed)")
sys.exit(1 if fails else 0)
