#!/usr/bin/env python3
"""logind-bridge stdin tests — no D-Bus, no GLib, no logind.

The bridge talks newline-delimited JSON on stdin. Lock.qml writes two commands
back-to-back (setLockedHint, then sleepReady) and the old reader took ONE line
per GLib wakeup, so the second sat in Python's buffer until the next write —
every lid-close suspend waited out the full delay timeout. These tests feed the
reader exactly that shape and assert every complete line is handled.

The dbus / gi modules are stubbed in sys.modules before the script is imported,
and Bridge is built without __init__ (no bus): only the reader is under test.
"""
import importlib.util
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "dotfiles", "quickshell", "scripts", "logind-bridge.py")


# ── stub the runtime deps the script imports at module level ────────────────
class FakeDBusException(Exception):
    def get_dbus_message(self):
        return str(self)


def _stub_modules():
    dbus = types.ModuleType("dbus")
    dbus.DBusException = FakeDBusException
    dbus_mainloop = types.ModuleType("dbus.mainloop")
    dbus_glib = types.ModuleType("dbus.mainloop.glib")
    dbus_glib.DBusGMainLoop = lambda **kw: None
    dbus.mainloop = dbus_mainloop
    dbus_mainloop.glib = dbus_glib

    gi = types.ModuleType("gi")
    repo = types.ModuleType("gi.repository")
    glib = types.ModuleType("GLib")
    glib.PRIORITY_DEFAULT = 0
    glib.IO_IN = 1
    glib.IO_HUP = 16
    glib.io_add_watch = lambda *a, **k: 1
    glib.timeout_add = lambda *a, **k: 1
    glib.source_remove = lambda *a, **k: True
    glib.MainLoop = object
    repo.GLib = glib
    gi.repository = repo

    sys.modules["dbus"] = dbus
    sys.modules["dbus.mainloop"] = dbus_mainloop
    sys.modules["dbus.mainloop.glib"] = dbus_glib
    sys.modules["gi"] = gi
    sys.modules["gi.repository"] = repo
    return glib


GLib = _stub_modules()
spec = importlib.util.spec_from_file_location("logind_bridge", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class FakeLoop:
    def __init__(self):
        self.quit_calls = 0

    def quit(self):
        self.quit_calls += 1


def make_bridge():
    """A Bridge with only what on_stdin needs: a pipe for stdin, a recording
    handle(), a loop whose quit() we can count."""
    b = mod.Bridge.__new__(mod.Bridge)
    r, w = os.pipe()
    b.inbuf = b""
    b.stdin_fd = r
    b.loop = FakeLoop()
    b.handled = []
    b.handle = b.handled.append
    return b, w


passed = 0
failed = 0


def check(name, cond):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL:", name)


def cmds(b):
    return [c.get("cmd") for c in b.handled]


# ── 1. two commands in ONE write → both handled on ONE wakeup ───────────────
b, w = make_bridge()
os.write(w, b'{"cmd": "setLockedHint", "value": true}\n{"cmd": "sleepReady"}\n')
keep = b.on_stdin(b.stdin_fd, GLib.IO_IN)
check("two lines in one write: both handled", cmds(b) == ["setLockedHint", "sleepReady"])
check("two lines in one write: value kept", b.handled[0].get("value") is True)
check("two lines in one write: watch kept", keep is True)
check("two lines in one write: buffer drained", b.inbuf == b"")

# ── 2. a line split across two wakeups is handled once it completes ─────────
os.write(w, b'{"cmd": "getBri')
b.on_stdin(b.stdin_fd, GLib.IO_IN)
check("partial line: not handled early", cmds(b) == ["setLockedHint", "sleepReady"])
os.write(w, b'ghtness"}\n{"cmd": "refresh"}\n')
b.on_stdin(b.stdin_fd, GLib.IO_IN)
check("partial line: completed and the next one too",
      cmds(b) == ["setLockedHint", "sleepReady", "getBrightness", "refresh"])

# ── 3. garbage never kills the reader or the lines around it ────────────────
os.write(w, b'not json at all\n[1, 2, 3]\n{"cmd": "listInhibitors"}\n')
keep = b.on_stdin(b.stdin_fd, GLib.IO_IN)
check("garbage line skipped, following command handled", cmds(b)[-1] == "listInhibitors")
check("garbage line: only dicts reach handle()", all(isinstance(c, dict) for c in b.handled))
check("garbage line: watch kept", keep is True)

# ── 4. a handler exception becomes an error event, not a crash ──────────────
events = []
mod.emit = lambda o: events.append(o)


def boom(c):
    raise RuntimeError("nope")


b.handle = boom
os.write(w, b'{"cmd": "setIdleHint"}\n')
keep = b.on_stdin(b.stdin_fd, GLib.IO_IN)
check("handler exception → error event", events and events[-1].get("event") == "error"
      and events[-1].get("cmd") == "setIdleHint" and "nope" in events[-1].get("error", ""))
check("handler exception: watch kept", keep is True)
b.handle = b.handled.append

# ── 5. EOF (the shell is gone): the last unterminated line counts, then quit ─
os.write(w, b'{"cmd": "sleepReady"}')      # no newline — the writer died mid-line
os.close(w)
b.on_stdin(b.stdin_fd, GLib.IO_IN)         # drains the bytes
keep = b.on_stdin(b.stdin_fd, GLib.IO_IN | GLib.IO_HUP)
check("EOF: unterminated last line handled", cmds(b)[-1] == "sleepReady")
check("EOF: loop quit once", b.loop.quit_calls == 1)
check("EOF: watch removed", keep is False)

# ── 6. HUP flagged together with data: the data still counts ────────────────
b2, w2 = make_bridge()
os.write(w2, b'{"cmd": "sleepReady"}\n')
os.close(w2)
keep = b2.on_stdin(b2.stdin_fd, GLib.IO_IN | GLib.IO_HUP)
check("HUP with data: command handled first", cmds(b2) == ["sleepReady"])
check("HUP with data: not quit until the read is empty", b2.loop.quit_calls == 0 and keep is True)
keep = b2.on_stdin(b2.stdin_fd, GLib.IO_HUP)
check("HUP then empty read: quit", b2.loop.quit_calls == 1 and keep is False)

print("logind-bridge: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
