#!/usr/bin/env python3
"""bt-agent.py — ewe's BlueZ pairing agent (the shell's D-Bus side).

Pairing anything that asks a question — "does 123456 match?", "type this PIN",
"may this phone pair?" — needs an org.bluez.Agent1 registered on the system
bus by SOMEONE in the session. bluetoothctl registers one for itself, which is
why the terminal always worked; Quickshell 0.3.1 has no agent at all and ewe
does not run blueman-applet (its tray icon duplicated the bar). So from the
GUI every device that needed an answer failed silently. This is that agent.

BtAgent.qml runs it as a Process and speaks newline-delimited JSON, the same
shape as kdeconnect-bridge.py (dbus-python + GLib — both already in ewe's
package set):

  stdout → events   {"event": "request", "id": 3, "kind": "confirm", ...}
  stdin  ← commands {"cmd": "reply", "id": 3, "ok": true, "value": "..."}

Capability KeyboardDisplay: BlueZ then negotiates the strongest flow both
sides support — numeric comparison for phones/laptops, passkey ENTRY for
keyboards (the passkey is shown here, typed on the keyboard), a PIN for legacy
gear, Just Works (no question) for headphones and speakers. The agent is also
the DEFAULT agent, so a Pair() started by anything that has no agent of its
own — Quickshell, ewe-bt (the Settings app), a GTK app — lands here: one
pairing dialog for the whole desktop.

Request kinds and what the dialog answers:
  confirm    passkey shown; does it match the device?     reply ok / rejected
  authorize  a device wants to pair with us (Just Works)  reply ok / rejected
  service    an untrusted device wants a profile (uuid)   reply ok / rejected
  pin        type the PIN the device shows                reply value (1-16 chars)
  passkey    type the 6-digit passkey the device shows    reply value (0-999999)
  display    passkey/PIN to type ON the device — no reply; BlueZ Cancels it or
             the device pairs (both close the dialog; "entered" counts keys)

Commands: reply · cancel (address → CancelPairing + reject its questions) ·
pair (address → Pair, then Trusted=true; result event carries a friendly
error) · connect (address) · quit.
"""

import json
import sys

try:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
except ImportError as e:
    print(json.dumps({"event": "fatal", "error": "missing python deps (python-dbus, python-gobject): %s" % e}), flush=True)
    sys.exit(0)

BLUEZ = "org.bluez"
AGENT_IFACE = "org.bluez.Agent1"
MGR_IFACE = "org.bluez.AgentManager1"
DEV_IFACE = "org.bluez.Device1"
ADAPTER_IFACE = "org.bluez.Adapter1"
PROPS = "org.freedesktop.DBus.Properties"
OM = "org.freedesktop.DBus.ObjectManager"
AGENT_PATH = "/org/ewe/bt/agent"
CAPABILITY = "KeyboardDisplay"

# service UUIDs a device may ask to use (AuthorizeService) — the dialog shows
# the words, not the number. Anything else shows as "a service".
SERVICES = {
    "0000110a": "audio from this computer",
    "0000110b": "audio playback",
    "0000110c": "media controls",
    "0000110d": "audio",
    "0000110e": "media controls",
    "00001108": "headset",
    "0000111e": "hands-free calls",
    "0000111f": "hands-free calls",
    "00001124": "keyboard / mouse input",
    "00001812": "keyboard / mouse input",
    "00001105": "file transfer (OBEX push)",
    "00001106": "file transfer",
    "0000112f": "contacts (phone book)",
    "00001132": "messages",
    "00001101": "a serial connection",
    "00001115": "networking (PAN)",
    "00001116": "internet sharing (PAN)",
    "0000180f": "battery reporting",
}

# BlueZ error names → what the person should read. The raw name is kept in
# the event too, for the log.
ERRORS = {
    "org.bluez.Error.AuthenticationCanceled": "Pairing cancelled",
    "org.bluez.Error.AuthenticationFailed": "Pairing failed — the codes did not match, or the device refused",
    "org.bluez.Error.AuthenticationRejected": "The device rejected the pairing",
    "org.bluez.Error.AuthenticationTimeout": "Pairing timed out — put the device in pairing mode and try again",
    "org.bluez.Error.AlreadyExists": "Already paired",
    "org.bluez.Error.AlreadyConnected": "Already connected",
    "org.bluez.Error.ConnectionAttemptFailed": "Could not reach the device — is it in pairing mode and nearby?",
    "org.bluez.Error.InProgress": "Still working on the last request — wait a moment",
    "org.bluez.Error.NotReady": "Bluetooth is off",
    "org.bluez.Error.NotAvailable": "The device is not available right now",
    "org.bluez.Error.DoesNotExist": "The device is gone — search again",
    "org.bluez.Error.NotPermitted": "Not permitted",
}
FAILED_HINTS = (
    ("br-connection-profile-unavailable", "No matching profile — for audio devices, check that PipeWire is running"),
    ("br-connection-page-timeout", "The device did not answer — is it switched on and nearby?"),
    ("br-connection-canceled", "Connection cancelled"),
    ("br-connection-refused", "The device refused the connection"),
    ("br-connection-key-missing", "The device forgot this computer — forget it here and pair again"),
    ("le-connection-abort-by-local", "Connection aborted"),
    ("Protocol not available", "No matching profile — for audio devices, check that PipeWire is running"),
    ("Input/output error", "The device did not answer — is it switched on and nearby?"),
    ("Host is down", "The device is off or out of range"),
)


def emit(obj):
    print(json.dumps(obj), flush=True)


def friendly(exc):
    """A DBusException → (human message, raw name)."""
    try:
        name = exc.get_dbus_name() or ""
        msg = exc.get_dbus_message() or ""
    except Exception:
        name, msg = "", str(exc)
    if name in ERRORS:
        return ERRORS[name], name
    for needle, text in FAILED_HINTS:
        if needle in msg:
            return text, name or msg
    return ("Failed: " + msg) if msg else "Failed", name or "unknown"


def service_name(uuid):
    return SERVICES.get(str(uuid)[:8].lower(), "a service")


class Agent(dbus.service.Object):
    """The org.bluez.Agent1 object. Every question becomes a `request` event
    with an id; the reply from the dialog resolves the pending D-Bus call."""

    def __init__(self, bus):
        super().__init__(bus, AGENT_PATH)
        self.bus = bus
        self.next_id = 1
        self.pending = {}    # id → {"kind", "path", "ok", "err"}
        self.display = {}    # device path → request id (DisplayPasskey / DisplayPinCode, no reply)
        self.registered = False

    # ── helpers ─────────────────────────────────────────────────────────────
    def dev_info(self, path):
        info = {"path": str(path), "address": "", "name": "", "icon": "", "paired": False, "trusted": False}
        try:
            p = dbus.Interface(self.bus.get_object(BLUEZ, path), PROPS).GetAll(DEV_IFACE)
            info["address"] = str(p.get("Address", ""))
            info["name"] = str(p.get("Alias") or p.get("Name") or p.get("Address", ""))
            info["icon"] = str(p.get("Icon", ""))
            info["paired"] = bool(p.get("Paired", False))
            info["trusted"] = bool(p.get("Trusted", False))
        except Exception:
            # a device that vanished mid-question — still show the question
            info["name"] = str(path).rsplit("dev_", 1)[-1].replace("_", ":")
            info["address"] = info["name"]
        return info

    def ask(self, kind, path, ok, err, **extra):
        rid = self.next_id
        self.next_id += 1
        self.pending[rid] = {"kind": kind, "path": str(path), "ok": ok, "err": err}
        ev = {"event": "request", "id": rid, "kind": kind, "device": self.dev_info(path)}
        ev.update(extra)
        emit(ev)

    def resolve(self, rid, accept, value):
        p = self.pending.pop(rid, None)
        if not p:
            return
        if not accept:
            p["err"](dbus.exceptions.DBusException("Rejected by user", name="org.bluez.Error.Rejected"))
            return
        kind = p["kind"]
        try:
            if kind == "pin":
                v = str(value or "").strip()
                if not (1 <= len(v) <= 16):
                    raise ValueError("a PIN is 1-16 characters")
                p["ok"](dbus.String(v))
            elif kind == "passkey":
                n = int(str(value or "").strip())
                if not (0 <= n <= 999999):
                    raise ValueError("a passkey is 0-999999")
                p["ok"](dbus.UInt32(n))
            else:
                p["ok"]()
        except Exception as e:
            emit({"event": "error", "error": "bad reply for %s: %s" % (kind, e)})
            p["err"](dbus.exceptions.DBusException("Rejected by user", name="org.bluez.Error.Rejected"))

    def reject_all(self, path=None, reason="Canceled"):
        for rid in list(self.pending):
            p = self.pending[rid]
            if path is not None and p["path"] != str(path):
                continue
            self.pending.pop(rid, None)
            try:
                p["err"](dbus.exceptions.DBusException(reason, name="org.bluez.Error." + reason))
            except Exception:
                pass
            emit({"event": "cancel", "id": rid})
        for dpath in list(self.display):
            if path is None or dpath == str(path):
                emit({"event": "cancel", "id": self.display.pop(dpath)})

    # ── org.bluez.Agent1 ────────────────────────────────────────────────────
    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        self.registered = False
        self.reject_all()
        emit({"event": "agent", "registered": False, "why": "released by bluez"})

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s", async_callbacks=("ok", "err"))
    def RequestPinCode(self, device, ok, err):
        self.ask("pin", device, ok, err)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        self.show(device, "pin", str(pincode), 0)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u", async_callbacks=("ok", "err"))
    def RequestPasskey(self, device, ok, err):
        self.ask("passkey", device, ok, err)

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        # called again for every key typed on the device — same id, new count
        self.show(device, "passkey", "%06d" % int(passkey), int(entered))

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="", async_callbacks=("ok", "err"))
    def RequestConfirmation(self, device, passkey, ok, err):
        self.ask("confirm", device, ok, err, passkey="%06d" % int(passkey))

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="", async_callbacks=("ok", "err"))
    def RequestAuthorization(self, device, ok, err):
        self.ask("authorize", device, ok, err)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="", async_callbacks=("ok", "err"))
    def AuthorizeService(self, device, uuid, ok, err):
        # a device we paired (or trust) may use any profile without a question —
        # bluez asks for untrusted devices only, but a paired one is ours
        info = self.dev_info(device)
        if info["trusted"] or info["paired"]:
            ok()
            return
        self.ask("service", device, ok, err, uuid=str(uuid), service=service_name(uuid))

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        # bluez withdraws the question: pairing finished (after a Display*),
        # timed out, or the other side gave up
        self.reject_all(reason="Canceled")

    def show(self, device, what, code, entered):
        path = str(device)
        rid = self.display.get(path)
        if rid is None:
            rid = self.next_id
            self.next_id += 1
            self.display[path] = rid
        emit({"event": "request", "id": rid, "kind": "display", "what": what, "passkey": code,
              "entered": entered, "device": self.dev_info(device)})

    # ── registration ────────────────────────────────────────────────────────
    def register(self):
        try:
            mgr = dbus.Interface(self.bus.get_object(BLUEZ, "/org/bluez"), MGR_IFACE)
            try:
                mgr.RegisterAgent(AGENT_PATH, CAPABILITY)
            except dbus.exceptions.DBusException as e:
                if e.get_dbus_name() != "org.bluez.Error.AlreadyExists":
                    raise
                mgr.UnregisterAgent(AGENT_PATH)
                mgr.RegisterAgent(AGENT_PATH, CAPABILITY)
            mgr.RequestDefaultAgent(AGENT_PATH)
            self.registered = True
            emit({"event": "agent", "registered": True})
        except dbus.exceptions.DBusException as e:
            self.registered = False
            emit({"event": "agent", "registered": False, "why": friendly(e)[0]})

    # ── commands from the dialog ────────────────────────────────────────────
    def find_device(self, address):
        want = str(address).upper()
        try:
            objs = dbus.Interface(self.bus.get_object(BLUEZ, "/"), OM).GetManagedObjects()
        except dbus.exceptions.DBusException:
            return None
        for path, ifaces in objs.items():
            d = ifaces.get(DEV_IFACE)
            if d and str(d.get("Address", "")).upper() == want:
                return str(path)
        return None

    def set_trusted(self, path):
        try:
            dbus.Interface(self.bus.get_object(BLUEZ, path), PROPS).Set(DEV_IFACE, "Trusted", dbus.Boolean(True))
        except dbus.exceptions.DBusException:
            pass

    def cmd_pair(self, address):
        path = self.find_device(address)
        if not path:
            emit({"event": "pair", "address": address, "ok": False, "error": "The device is gone — search again"})
            return
        dev = dbus.Interface(self.bus.get_object(BLUEZ, path), DEV_IFACE)

        def done():
            # bluez accepts ONE connection from an untrusted device and refuses
            # the reconnect that follows — trust is what makes a pairing stick.
            # Then connect: bluez does not on pair, and the tap that started
            # this was the intent (the same three steps ewe-bt runs for the
            # Settings app, so both entry points behave alike)
            self.set_trusted(path)
            emit({"event": "pair", "address": address, "ok": True})
            self.cmd_connect(address)

        def failed(e):
            text, raw = friendly(e)
            if raw == "org.bluez.Error.AlreadyExists":       # paired after all — just connect
                self.set_trusted(path)
                emit({"event": "pair", "address": address, "ok": True})
                self.cmd_connect(address)
                return
            emit({"event": "pair", "address": address, "ok": False, "error": text, "raw": raw})

        dev.Pair(reply_handler=done, error_handler=failed, timeout=180)

    def cmd_connect(self, address):
        path = self.find_device(address)
        if not path:
            emit({"event": "connect", "address": address, "ok": False, "error": "The device is gone — search again"})
            return
        dev = dbus.Interface(self.bus.get_object(BLUEZ, path), DEV_IFACE)
        self.set_trusted(path)

        def done():
            emit({"event": "connect", "address": address, "ok": True})

        def failed(e):
            text, raw = friendly(e)
            if raw == "org.bluez.Error.AlreadyConnected":
                emit({"event": "connect", "address": address, "ok": True})
                return
            emit({"event": "connect", "address": address, "ok": False, "error": text, "raw": raw})

        dev.Connect(reply_handler=done, error_handler=failed, timeout=60)

    def cmd_cancel(self, address):
        path = self.find_device(address) if address else None
        self.reject_all(path=path, reason="Canceled")
        if path:
            try:
                dbus.Interface(self.bus.get_object(BLUEZ, path), DEV_IFACE).CancelPairing()
            except dbus.exceptions.DBusException:
                pass


def main():
    DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SystemBus()
    except dbus.exceptions.DBusException as e:
        emit({"event": "fatal", "error": "no system bus: %s" % e})
        return
    agent = Agent(bus)
    loop = GLib.MainLoop()

    # bluez comes and goes (service restart, adapter re-plug): (re)register
    # whenever it owns its name, and say so when it does not
    def owner_changed(owner):
        if owner:
            agent.register()
        else:
            agent.registered = False
            agent.reject_all()
            emit({"event": "agent", "registered": False, "why": "bluetooth.service is not running"})
    bus.watch_name_owner(BLUEZ, owner_changed)

    # a device that pairs while a Display* question is up closes it — bluez
    # Cancels those too, but a Paired flip is the surer signal
    def props_changed(iface, changed, invalidated, path=None):
        if iface != DEV_IFACE or path not in agent.display:
            return
        if bool(changed.get("Paired", False)):
            emit({"event": "cancel", "id": agent.display.pop(path)})
    bus.add_signal_receiver(props_changed, dbus_interface=PROPS, signal_name="PropertiesChanged", path_keyword="path")

    def on_stdin(chan, cond):
        if cond & (GLib.IO_HUP | GLib.IO_ERR):
            loop.quit()
            return False
        line = sys.stdin.readline()
        if not line:
            loop.quit()
            return False
        try:
            c = json.loads(line)
        except ValueError:
            return True
        cmd = c.get("cmd")
        try:
            if cmd == "reply":
                agent.resolve(int(c.get("id", 0)), bool(c.get("ok", False)), c.get("value", ""))
            elif cmd == "cancel":
                agent.cmd_cancel(str(c.get("address", "")))
            elif cmd == "pair":
                agent.cmd_pair(str(c.get("address", "")))
            elif cmd == "connect":
                agent.cmd_connect(str(c.get("address", "")))
            elif cmd == "register":
                agent.register()
            elif cmd == "ping":
                emit({"event": "pong", "registered": agent.registered})
            elif cmd == "quit":
                loop.quit()
                return False
        except Exception as e:      # never die on a bad command — report it
            emit({"event": "error", "error": "%s: %s" % (cmd, e)})
        return True
    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)

    emit({"event": "hello", "capability": CAPABILITY})
    loop.run()
    if agent.registered:
        try:
            dbus.Interface(bus.get_object(BLUEZ, "/org/bluez"), MGR_IFACE).UnregisterAgent(AGENT_PATH)
        except Exception:
            pass


if __name__ == "__main__":
    main()
