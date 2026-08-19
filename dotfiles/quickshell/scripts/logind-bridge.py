#!/usr/bin/env python3
"""logind-bridge.py — D-Bus bridge between systemd-logind and the QML shell.

Quickshell has no generic QML D-Bus client, so this long-lived helper owns ALL
org.freedesktop.login1 traffic (dbus-python + GLib main loop — the same deps
kdeconnect-bridge.py already needs). Logind.qml runs it as a Process and speaks
newline-delimited JSON:

  stdout → events   {"event": "...", ...}   (signal relays, state pushes)
  stdin  ← commands {"cmd": "...", ...}     (sleepReady, setBrightness, hints)

Why a process and not `busctl` one-shots like the rest of the shell: locking
*before* suspend requires a DELAY INHIBITOR, and an inhibitor lives exactly as
long as the file descriptor logind hands back. A one-shot call would close that
fd on exit and the inhibitor would evaporate. So the fd is held here for the
whole session, released the moment the shell says it is ready to sleep, and
re-taken on resume.

The delay is a loaded gun: whatever we do not release, logind waits out for the
full InhibitDelayMaxSec (5s by default) on EVERY suspend. So the release is also
armed with a timer — if the shell never answers, we let go anyway.
"""

import json
import os
import sys

try:
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
except ImportError as e:
    print(json.dumps({"event": "fatal", "error": "missing python deps (python-dbus, python-gobject): %s" % e}), flush=True)
    sys.exit(0)

SERVICE = "org.freedesktop.login1"
MANAGER_PATH = "/org/freedesktop/login1"
MANAGER_IFACE = "org.freedesktop.login1.Manager"
SESSION_IFACE = "org.freedesktop.login1.Session"
USER_IFACE = "org.freedesktop.login1.User"
PROPS = "org.freedesktop.DBus.Properties"

BACKLIGHT_DIR = "/sys/class/backlight"
LEDS_DIR = "/sys/class/leds"

# what we hold a delay inhibitor for (released on sleepReady, re-taken on resume)
INHIBIT_WHAT = "sleep:shutdown"

# held in BLOCK mode for the whole session: logind's lid fallback is
# HandleLidSwitch=suspend (10-hypr-shell-lid.conf), which must only fire where
# the shell is NOT running (greeter, TTY, crashed shell). While we are alive,
# clamshell policy is Lid.qml's — this lock is how logind knows to stand down.
LID_INHIBIT_WHAT = "handle-lid-switch"


def emit(obj):
    print(json.dumps(obj), flush=True)


def plain(v):
    """dbus type → plain JSON-serializable python."""
    if isinstance(v, (dbus.String, dbus.ObjectPath, dbus.Signature)):
        return str(v)
    if isinstance(v, dbus.Boolean):
        return bool(v)
    if isinstance(v, (dbus.Byte, dbus.Int16, dbus.UInt16, dbus.Int32, dbus.UInt32, dbus.Int64, dbus.UInt64)):
        return int(v)
    if isinstance(v, dbus.Double):
        return float(v)
    if isinstance(v, (dbus.Array, list, tuple)):
        return [plain(x) for x in v]
    if isinstance(v, (dbus.Dictionary, dict)):
        return {str(k): plain(x) for k, x in v.items()}
    return v if isinstance(v, (str, int, float, bool)) or v is None else str(v)


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


class Bridge:
    def __init__(self):
        DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SystemBus()          # login1 lives on the SYSTEM bus
        # a second, optional connection purely to ask who owns
        # org.freedesktop.ScreenSaver — see screensaver_owner()
        try:
            self.session_bus = dbus.SessionBus()
        except dbus.DBusException:
            self.session_bus = None
        self.loop = GLib.MainLoop()
        self.fd = None                       # the delay inhibitor
        self.lid_fd = None                   # the handle-lid-switch block
        self.release_timer = None
        self.session_path = self.find_session()
        self.delay_ms = self.read_delay_ms()
        self.backlight = self.find_device(BACKLIGHT_DIR, "backlight", None)
        self.kbd = self.find_device(LEDS_DIR, "leds", "kbd_backlight")

        sub = self.bus.add_signal_receiver
        sub(self.on_prepare_sleep, dbus_interface=MANAGER_IFACE, signal_name="PrepareForSleep",
            bus_name=SERVICE, path=MANAGER_PATH)
        sub(self.on_prepare_shutdown, dbus_interface=MANAGER_IFACE, signal_name="PrepareForShutdown",
            bus_name=SERVICE, path=MANAGER_PATH)
        if self.session_path:
            # `loginctl lock-session` lands here — the shell documented this
            # recovery path for years while nothing actually implemented it
            sub(self.on_lock, dbus_interface=SESSION_IFACE, signal_name="Lock",
                bus_name=SERVICE, path=self.session_path)
            sub(self.on_unlock, dbus_interface=SESSION_IFACE, signal_name="Unlock",
                bus_name=SERVICE, path=self.session_path)
            sub(self.on_session_props, dbus_interface=PROPS, signal_name="PropertiesChanged",
                bus_name=SERVICE, path=self.session_path)

        GLib.io_add_watch(sys.stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.on_stdin)

    # ── objects ─────────────────────────────────────────────────────────────
    def manager(self):
        return dbus.Interface(self.bus.get_object(SERVICE, MANAGER_PATH), MANAGER_IFACE)

    def session(self):
        return dbus.Interface(self.bus.get_object(SERVICE, self.session_path), SESSION_IFACE)

    def prop(self, path, iface, name):
        o = self.bus.get_object(SERVICE, path)
        return plain(dbus.Interface(o, PROPS).Get(iface, name))

    def session_has_seat(self, path):
        """A session we can actually drive has a SEAT. `systemd --user` runs in a
        seatless session of class "manager", and SetBrightness / SetLockedHint
        against that one silently do nothing useful — so seat is the filter."""
        try:
            seat = self.prop(path, SESSION_IFACE, "Seat")
        except dbus.DBusException:
            return False
        if isinstance(seat, (list, tuple)):     # (id, objectpath) struct
            return bool(seat) and bool(seat[0])
        return bool(seat)

    def find_session(self):
        """Our graphical login session, most-authoritative source first.

        GetSessionByPID alone is not enough: it raises NoSessionForPID for any
        process outside a session, and where the shell is started from a user
        unit it can resolve to the seatless "manager" session instead of the one
        on seat0. The User object's Display property is the answer that is
        actually about the graphical session, so it outranks the pid lookup."""
        cands = []
        sid = os.environ.get("XDG_SESSION_ID", "")
        if sid:
            try:
                cands.append(str(self.manager().GetSession(sid)))
            except dbus.DBusException:
                pass
        try:
            user_path = str(self.manager().GetUser(dbus.UInt32(os.getuid())))
            disp = self.prop(user_path, USER_IFACE, "Display")
            if disp and len(disp) > 1 and disp[1]:
                cands.append(str(disp[1]))
        except (dbus.DBusException, IndexError, TypeError):
            pass
        try:
            cands.append(str(self.manager().GetSessionByPID(dbus.UInt32(os.getpid()))))
        except dbus.DBusException:
            pass

        for p in cands:
            if p and self.session_has_seat(p):
                return p
        return cands[0] if cands else ""

    def read_delay_ms(self):
        """Stay comfortably inside logind's own ceiling — overrunning it means
        logind suspends out from under us mid-lock."""
        us = None
        try:
            us = self.prop(MANAGER_PATH, MANAGER_IFACE, "InhibitDelayMaxUSec")
        except dbus.DBusException:
            pass
        ms = (int(us) // 1000) if us else 5000
        return max(1000, min(int(ms * 0.8), 8000))

    def find_device(self, root, subsystem, needle):
        """First usable brightness device under a sysfs class dir. Raw panel
        backlights are preferred over the acpi_video stubs, which often exist
        alongside and do nothing."""
        try:
            names = os.listdir(root)
        except OSError:
            return None
        if needle:
            names = [n for n in names if needle in n]
        names.sort(key=lambda n: (n.startswith("acpi_video"), n))
        for n in names:
            mx = read_int(os.path.join(root, n, "max_brightness"))
            if mx:
                return {"subsystem": subsystem, "name": n, "max": mx,
                        "path": os.path.join(root, n)}
        return None

    def device_state(self, dev):
        if not dev:
            return None
        cur = read_int(os.path.join(dev["path"], "brightness"))
        cur = 0 if cur is None else cur
        return {"name": dev["name"], "max": dev["max"], "value": cur,
                "percent": (cur / dev["max"]) if dev["max"] else 0}

    # ── the delay inhibitor ─────────────────────────────────────────────────
    def take_inhibitor(self):
        if self.fd is not None:
            return
        try:
            r = self.manager().Inhibit(INHIBIT_WHAT, "hypr-shell",
                                       "Lock the session before sleep", "delay")
            # dbus-python hands back a UnixFd wrapper; .take() transfers the fd
            self.fd = r.take() if hasattr(r, "take") else int(r)
        except dbus.DBusException as e:
            self.fd = None
            emit({"event": "error", "cmd": "inhibit", "error": e.get_dbus_message()})

    def take_lid_inhibitor(self):
        """Unlike the delay inhibitor this is never released mid-session: it is
        the shell's claim on the lid switch, and only dropping the fd (process
        exit, crash included) hands the lid back to logind's suspend fallback."""
        if self.lid_fd is not None:
            return
        try:
            r = self.manager().Inhibit(LID_INHIBIT_WHAT, "hypr-shell",
                                       "Shell owns clamshell policy (Lid.qml)", "block")
            self.lid_fd = r.take() if hasattr(r, "take") else int(r)
        except dbus.DBusException as e:
            self.lid_fd = None
            emit({"event": "error", "cmd": "lidInhibit", "error": e.get_dbus_message()})

    def release_inhibitor(self):
        if self.release_timer is not None:
            GLib.source_remove(self.release_timer)
            self.release_timer = None
        if self.fd is None:
            return
        try:
            os.close(self.fd)
        except OSError:
            pass
        self.fd = None

    def _release_timeout(self):
        self.release_timer = None
        emit({"event": "sleepTimeout", "ms": self.delay_ms})
        self.release_inhibitor()
        return False

    def _arm_release(self):
        if self.release_timer is None:
            self.release_timer = GLib.timeout_add(self.delay_ms, self._release_timeout)

    # ── signals ─────────────────────────────────────────────────────────────
    def on_prepare_sleep(self, starting):
        if bool(starting):
            # we hold the delay: the shell now has self.delay_ms to lock up
            emit({"event": "sleep", "starting": True, "delayMs": self.delay_ms,
                  "inhibited": self.fd is not None})
            self._arm_release()
        else:
            self.take_inhibitor()          # re-arm for the next cycle
            emit({"event": "sleep", "starting": False})

    def on_prepare_shutdown(self, starting):
        if bool(starting):
            emit({"event": "shutdown", "starting": True, "delayMs": self.delay_ms})
            self._arm_release()
        else:
            emit({"event": "shutdown", "starting": False})

    def on_lock(self):
        emit({"event": "lock"})

    def on_unlock(self):
        emit({"event": "unlock"})

    def on_session_props(self, iface, changed, invalidated):
        if str(iface) != SESSION_IFACE:
            return
        c = plain(changed)
        out = {}
        if "LockedHint" in c:
            out["lockedHint"] = bool(c["LockedHint"])
        if "IdleHint" in c:
            out["idleHint"] = bool(c["IdleHint"])
        if out:
            out["event"] = "session"
            emit(out)

    # ── commands from QML ───────────────────────────────────────────────────
    def on_stdin(self, source, condition):
        if condition & GLib.IO_HUP:
            self.loop.quit()
            return False
        line = sys.stdin.readline()
        if line == "":
            self.loop.quit()
            return False
        try:
            c = json.loads(line)
        except ValueError:
            return True
        try:
            self.handle(c)
        except dbus.DBusException as e:
            emit({"event": "error", "cmd": c.get("cmd", "?"), "error": e.get_dbus_message()})
        except Exception as e:      # never die on a bad command
            emit({"event": "error", "cmd": c.get("cmd", "?"), "error": str(e)})
        return True

    def handle(self, c):
        cmd = c.get("cmd", "")
        if cmd == "sleepReady":
            # the shell finished locking — stop holding suspend up
            self.release_inhibitor()
        elif cmd == "setBrightness":
            self.set_brightness(c)
        elif cmd == "getBrightness":
            self.push_brightness()
        elif cmd == "setLockedHint":
            self.session().SetLockedHint(dbus.Boolean(bool(c.get("value", False))))
        elif cmd == "setIdleHint":
            self.session().SetIdleHint(dbus.Boolean(bool(c.get("value", False))))
        elif cmd == "lockSession":
            self.session().Lock()
        elif cmd == "listInhibitors":
            self.push_inhibitors()
        elif cmd == "refresh":
            self.push_hello()

    def set_brightness(self, c):
        which = c.get("device", "backlight")
        dev = self.backlight if which == "backlight" else self.kbd
        if not dev:
            emit({"event": "error", "cmd": "setBrightness", "error": "no %s device" % which})
            return
        if "percent" in c:
            val = int(round(max(0.0, min(1.0, float(c["percent"]))) * dev["max"]))
        else:
            val = int(max(0, min(dev["max"], int(c.get("value", 0)))))
        # logind writes it for us — no udev rule, no setuid helper, no root
        self.session().SetBrightness(dev["subsystem"], dev["name"], dbus.UInt32(val))
        self.push_brightness()

    def push_brightness(self):
        emit({"event": "brightness",
              "backlight": self.device_state(self.backlight),
              "kbd": self.device_state(self.kbd)})

    # ── who is keeping this machine awake ───────────────────────────────────
    def screensaver_owner(self):
        """The process owning org.freedesktop.ScreenSaver, if any.

        We deliberately do NOT own this name ourselves: hypridle implements it
        (that is what `ignore_dbus_inhibit = false` honours), and two owners
        would fight over it. Reporting who holds it tells the user whether app
        inhibits — "don't blank, I'm playing a video" — are being heard at all."""
        if not self.session_bus:
            return ""
        try:
            d = dbus.Interface(
                self.session_bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus"),
                "org.freedesktop.DBus")
            if not bool(d.NameHasOwner("org.freedesktop.ScreenSaver")):
                return ""
            pid = int(d.GetConnectionUnixProcessID(str(d.GetNameOwner("org.freedesktop.ScreenSaver"))))
            try:
                with open("/proc/%d/comm" % pid) as f:
                    return f.read().strip()
            except OSError:
                return "pid %d" % pid
        except dbus.DBusException:
            return ""

    def push_inhibitors(self):
        out = []
        try:
            for it in self.manager().ListInhibitors():
                what, who, why, mode, uid, pid = [plain(x) for x in it]
                out.append({"what": what, "who": who, "why": why,
                            "mode": mode, "uid": uid, "pid": pid})
        except dbus.DBusException as e:
            emit({"event": "error", "cmd": "listInhibitors", "error": e.get_dbus_message()})
            return
        emit({"event": "inhibitors", "list": out, "screensaver": self.screensaver_owner()})

    def push_hello(self):
        locked, idle = False, False
        if self.session_path:
            try:
                locked = bool(self.prop(self.session_path, SESSION_IFACE, "LockedHint"))
                idle = bool(self.prop(self.session_path, SESSION_IFACE, "IdleHint"))
            except dbus.DBusException:
                pass
        emit({"event": "hello",
              "session": self.session_path,
              "inhibited": self.fd is not None,
              "delayMs": self.delay_ms,
              "lockedHint": locked,
              "idleHint": idle,
              "backlight": self.device_state(self.backlight),
              "kbd": self.device_state(self.kbd)})

    # ── main ────────────────────────────────────────────────────────────────
    def run(self):
        if not self.session_path:
            emit({"event": "fatal", "error": "no logind session for this process"})
            return
        self.take_inhibitor()
        self.take_lid_inhibitor()
        self.push_hello()
        self.loop.run()

    def shutdown(self):
        self.release_inhibitor()
        if self.lid_fd is not None:
            try:
                os.close(self.lid_fd)
            except OSError:
                pass
            self.lid_fd = None


if __name__ == "__main__":
    b = None
    try:
        b = Bridge()
        b.run()
    except KeyboardInterrupt:
        pass
    finally:
        # never leave a delay inhibitor behind — it would stall every suspend
        # on the machine for InhibitDelayMaxSec until the fd is reaped
        if b is not None:
            b.shutdown()
