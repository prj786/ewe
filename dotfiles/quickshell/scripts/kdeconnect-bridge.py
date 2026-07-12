#!/usr/bin/env python3
"""kdeconnect-bridge.py — D-Bus bridge between kdeconnectd and the QML shell.

Quickshell has no generic QML D-Bus client, so this long-lived helper owns ALL
KDE Connect D-Bus traffic (dbus-python + GLib main loop — both already shipped
by hypr-shell's package set). The QML side (KdeConnect.qml) runs it as a
Process and speaks newline-delimited JSON:

  stdout → events  {"event": "...", ...}   (state pushes, signal relays)
  stdin  ← commands {"cmd": "...", ...}    (pair, dismiss, send message, …)

Interfaces verified against kdeconnect 26.04.x source (device / battery /
notifications / conversations). Every reply is one JSON line; the bridge never
crashes on a bad device — errors surface as {"event":"error", ...}.
"""

import json
import os
import subprocess
import sys

try:
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
except ImportError as e:
    print(json.dumps({"event": "fatal", "error": "missing python deps (python-dbus, python-gobject): %s" % e}), flush=True)
    sys.exit(0)

SERVICE = "org.kde.kdeconnect"
DAEMON_PATH = "/modules/kdeconnect"
DAEMON_IFACE = "org.kde.kdeconnect.daemon"
DEV_IFACE = "org.kde.kdeconnect.device"
BATT_IFACE = "org.kde.kdeconnect.device.battery"
NOTIF_IFACE = "org.kde.kdeconnect.device.notifications"
NOTIF_OBJ_IFACE = "org.kde.kdeconnect.device.notifications.notification"
CONV_IFACE = "org.kde.kdeconnect.device.conversations"
PROPS = "org.freedesktop.DBus.Properties"

# pairState ints from core/pairstate.h
PAIR_NOT, PAIR_REQUESTED, PAIR_BY_PEER, PAIR_PAIRED = 0, 1, 2, 3


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


class Bridge:
    def __init__(self):
        DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SessionBus()
        self.loop = GLib.MainLoop()
        self.daemon_up = False
        self.devices = {}     # id -> dict

        # global (no-path-filter) subscriptions: one receiver per signal kind,
        # the device id comes out of the object path — no per-device churn
        sub = self.bus.add_signal_receiver
        sub(self.on_daemon_changed, dbus_interface=DAEMON_IFACE, signal_name="deviceAdded", bus_name=SERVICE)
        sub(self.on_daemon_changed, dbus_interface=DAEMON_IFACE, signal_name="deviceRemoved", bus_name=SERVICE)
        sub(self.on_daemon_changed, dbus_interface=DAEMON_IFACE, signal_name="deviceListChanged", bus_name=SERVICE)
        sub(self.on_daemon_changed, dbus_interface=DAEMON_IFACE, signal_name="deviceVisibilityChanged", bus_name=SERVICE)
        sub(self.on_dev_signal, dbus_interface=DEV_IFACE, signal_name="reachableChanged", path_keyword="path")
        sub(self.on_dev_signal, dbus_interface=DEV_IFACE, signal_name="pairStateChanged", path_keyword="path")
        sub(self.on_dev_signal, dbus_interface=DEV_IFACE, signal_name="pluginsChanged", path_keyword="path")
        sub(self.on_dev_signal, dbus_interface=DEV_IFACE, signal_name="nameChanged", path_keyword="path")
        sub(self.on_pairing_failed, dbus_interface=DEV_IFACE, signal_name="pairingFailed", path_keyword="path")
        sub(self.on_battery, dbus_interface=BATT_IFACE, signal_name="refreshed", path_keyword="path")
        sub(self.on_notif_change, dbus_interface=NOTIF_IFACE, signal_name="notificationPosted", path_keyword="path")
        sub(self.on_notif_change, dbus_interface=NOTIF_IFACE, signal_name="notificationUpdated", path_keyword="path")
        sub(self.on_notif_removed, dbus_interface=NOTIF_IFACE, signal_name="notificationRemoved", path_keyword="path")
        sub(self.on_notifs_cleared, dbus_interface=NOTIF_IFACE, signal_name="allNotificationsRemoved", path_keyword="path")
        sub(self.on_notif_ready, dbus_interface=NOTIF_OBJ_IFACE, signal_name="ready", path_keyword="path")
        sub(self.on_message, dbus_interface=CONV_IFACE, signal_name="conversationCreated", path_keyword="path")
        sub(self.on_message, dbus_interface=CONV_IFACE, signal_name="conversationUpdated", path_keyword="path")
        sub(self.on_conv_removed, dbus_interface=CONV_IFACE, signal_name="conversationRemoved", path_keyword="path")
        # daemon appearing/disappearing (restart, first activation)
        self.bus.watch_name_owner(SERVICE, self.on_owner_changed)

        GLib.io_add_watch(sys.stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.on_stdin)

    # ── daemon lifecycle ────────────────────────────────────────────────────
    def ensure_daemon(self):
        try:
            if self.bus.name_has_owner(SERVICE):
                return True
        except dbus.DBusException:
            return False
        # try D-Bus activation, then the binary directly (Arch: /usr/bin or /usr/lib)
        try:
            self.bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus").StartServiceByName(
                SERVICE, dbus.UInt32(0), dbus_interface="org.freedesktop.DBus")
            return True
        except dbus.DBusException:
            pass
        for exe in ("/usr/bin/kdeconnectd", "/usr/lib/kdeconnectd"):
            if os.path.exists(exe):
                try:
                    subprocess.Popen([exe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     start_new_session=True)
                    return True   # owner-changed watch will fire when it's up
                except OSError:
                    pass
        return False

    def installed(self):
        for p in ("/usr/bin/kdeconnectd", "/usr/lib/kdeconnectd", "/usr/bin/kdeconnect-cli"):
            if os.path.exists(p):
                return True
        return False

    def on_owner_changed(self, owner):
        up = owner != ""
        if up == self.daemon_up:
            return
        self.daemon_up = up
        emit({"event": "daemon", "running": up})
        if up:
            GLib.timeout_add(600, self._initial_refresh)   # let it enumerate links first
        else:
            self.devices = {}
            self.push_devices()

    def _initial_refresh(self):
        self.refresh_devices()
        return False

    # ── device state ────────────────────────────────────────────────────────
    def dev_path(self, dev_id):
        return DAEMON_PATH + "/devices/" + dev_id

    def id_from_path(self, path):
        parts = path.split("/")
        return parts[4] if len(parts) > 4 else ""

    def get_props(self, path, iface):
        try:
            o = self.bus.get_object(SERVICE, path)
            return plain(dbus.Interface(o, PROPS).GetAll(iface))
        except dbus.DBusException:
            return None

    def read_device(self, dev_id):
        p = self.get_props(self.dev_path(dev_id), DEV_IFACE)
        if p is None:
            return None
        d = {
            "id": dev_id,
            "name": p.get("name", dev_id),
            "type": p.get("type", ""),
            "isReachable": bool(p.get("isReachable", False)),
            "isPaired": bool(p.get("isPaired", False)),
            "pairState": int(p.get("pairState", 0)),
            "pairRequestedByPeer": bool(p.get("isPairRequestedByPeer", False)),
            "plugins": p.get("supportedPlugins", []),
            "batteryCharge": -1, "isCharging": False,
        }
        b = self.get_props(self.dev_path(dev_id) + "/battery", BATT_IFACE)
        if b is not None:
            d["batteryCharge"] = int(b.get("charge", -1))
            d["isCharging"] = bool(b.get("isCharging", False))
        return d

    def refresh_devices(self):
        try:
            daemon = dbus.Interface(self.bus.get_object(SERVICE, DAEMON_PATH), DAEMON_IFACE)
            ids = plain(daemon.devices(False, False))
            self.daemon_up = True
        except dbus.DBusException:
            self.daemon_up = False
            self.devices = {}
            emit({"event": "daemon", "running": False})
            self.push_devices()
            return
        self.devices = {}
        for i in ids:
            d = self.read_device(i)
            if d:
                self.devices[i] = d
        self.push_devices()

    def push_devices(self):
        emit({"event": "devices", "list": sorted(self.devices.values(), key=lambda d: d["name"].lower())})

    def refresh_one(self, dev_id):
        d = self.read_device(dev_id)
        if d:
            self.devices[dev_id] = d
        else:
            self.devices.pop(dev_id, None)
        self.push_devices()

    # ── daemon / device signals ──────────────────────────────────────────────
    def on_daemon_changed(self, *args):
        self.refresh_devices()

    def on_dev_signal(self, *args, path=""):
        self.refresh_one(self.id_from_path(path))

    def on_pairing_failed(self, error, path=""):
        emit({"event": "pairError", "deviceId": self.id_from_path(path), "error": plain(error)})
        self.refresh_one(self.id_from_path(path))

    def on_battery(self, is_charging, charge, path=""):
        dev_id = self.id_from_path(path)
        if dev_id in self.devices:
            self.devices[dev_id]["batteryCharge"] = int(charge)
            self.devices[dev_id]["isCharging"] = bool(is_charging)
        emit({"event": "battery", "deviceId": dev_id, "charge": int(charge), "isCharging": bool(is_charging)})

    # ── phone notifications ──────────────────────────────────────────────────
    def read_notification(self, dev_id, pub_id):
        p = self.get_props(self.dev_path(dev_id) + "/notifications/" + pub_id, NOTIF_OBJ_IFACE)
        if p is None:
            return None
        return {
            "id": pub_id,
            "appName": p.get("appName", ""), "title": p.get("title", ""),
            "text": p.get("text", ""), "ticker": p.get("ticker", ""),
            "iconPath": p.get("iconPath", ""), "dismissable": bool(p.get("dismissable", False)),
            "replyId": p.get("replyId", ""), "silent": bool(p.get("silent", False)),
        }

    def push_notifications(self, dev_id):
        try:
            o = self.bus.get_object(SERVICE, self.dev_path(dev_id) + "/notifications")
            ids = plain(dbus.Interface(o, NOTIF_IFACE).activeNotifications())
        except dbus.DBusException:
            ids = []
        out = []
        for n in ids:
            item = self.read_notification(dev_id, n)
            if item and not item["silent"]:
                out.append(item)
        emit({"event": "notifications", "deviceId": dev_id, "list": out})

    def on_notif_change(self, pub_id, path=""):
        self.push_notifications(self.id_from_path(path))

    def on_notif_removed(self, pub_id, path=""):
        self.push_notifications(self.id_from_path(path))

    def on_notifs_cleared(self, path=""):
        emit({"event": "notifications", "deviceId": self.id_from_path(path), "list": []})

    def on_notif_ready(self, path=""):
        # props became complete after the post — path is .../notifications/<id>
        self.push_notifications(self.id_from_path(path))

    # ── SMS / conversations ──────────────────────────────────────────────────
    def norm_message(self, m):
        m = plain(m)
        if not isinstance(m, dict):
            return None
        addrs = []
        for a in (m.get("addresses") or []):
            if isinstance(a, dict) and a.get("address"):
                addrs.append(str(a["address"]))
            elif isinstance(a, str):
                addrs.append(a)
        return {
            "threadId": int(m.get("thread_id", -1)),
            "body": m.get("body", ""),
            "date": int(m.get("date", 0)),
            "type": int(m.get("type", 1)),          # 1 = received, 2 = sent
            "read": int(m.get("read", 1)),
            "addresses": addrs,
            "uid": int(m.get("u_id", m.get("uID", 0)) or 0),
            "multitarget": len(addrs) > 1,
            "hasAttachments": bool(m.get("attachments")),
            "event": int(m.get("event", 1) or 1),   # 1 = sms/text
        }

    def conv_iface(self, dev_id):
        o = self.bus.get_object(SERVICE, self.dev_path(dev_id) + "/conversations")
        return dbus.Interface(o, CONV_IFACE)

    def on_message(self, msg, path=""):
        m = self.norm_message(msg)
        if m:
            emit({"event": "message", "deviceId": self.id_from_path(path), "msg": m})

    def on_conv_removed(self, conv_id, path=""):
        emit({"event": "conversationRemoved", "deviceId": self.id_from_path(path), "threadId": int(plain(conv_id))})

    # ── commands from QML ────────────────────────────────────────────────────
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
        except Exception as e:  # never die on a bad command
            emit({"event": "error", "cmd": c.get("cmd", "?"), "error": str(e)})
        return True

    def dev_iface(self, dev_id):
        return dbus.Interface(self.bus.get_object(SERVICE, self.dev_path(dev_id)), DEV_IFACE)

    def plugin(self, dev_id, sub, iface):
        return dbus.Interface(self.bus.get_object(SERVICE, self.dev_path(dev_id) + "/" + sub), iface)

    def handle(self, c):
        cmd, dev = c.get("cmd", ""), c.get("deviceId", "")
        if cmd == "refresh":
            if self.ensure_daemon():
                try:
                    dbus.Interface(self.bus.get_object(SERVICE, DAEMON_PATH), DAEMON_IFACE).forceOnNetworkChange()
                except dbus.DBusException:
                    pass
            self.refresh_devices()
        elif cmd == "pair":
            self.dev_iface(dev).requestPairing()
        elif cmd == "unpair":
            self.dev_iface(dev).unpair()
        elif cmd == "acceptPair":
            self.dev_iface(dev).acceptPairing()
        elif cmd == "cancelPair":
            self.dev_iface(dev).cancelPairing()
        elif cmd == "notifications":
            self.push_notifications(dev)
        elif cmd == "dismiss":
            o = self.bus.get_object(SERVICE, self.dev_path(dev) + "/notifications/" + c["id"])
            dbus.Interface(o, NOTIF_OBJ_IFACE).dismiss()
        elif cmd == "replyNotif":
            self.plugin(dev, "notifications", NOTIF_IFACE).sendReply(c["replyId"], c["text"])
        elif cmd == "requestConversations":
            self.conv_iface(dev).requestAllConversationThreads()
        elif cmd == "requestConversation":
            self.conv_iface(dev).requestConversation(
                dbus.Int64(int(c["threadId"])), dbus.Int32(int(c.get("start", 0))), dbus.Int32(int(c.get("end", 30))))
        elif cmd == "sendMessage":
            self.conv_iface(dev).replyToConversation(
                dbus.Int64(int(c["threadId"])), c["text"], dbus.Array([], signature="v"))
        elif cmd == "sendToAddress":
            addr = dbus.Dictionary({"address": dbus.String(c["address"])}, signature="sv")
            self.conv_iface(dev).sendWithoutConversation(
                dbus.Array([addr], signature="v"), c["text"], dbus.Array([], signature="v"))
        elif cmd == "ring":
            self.plugin(dev, "findmyphone", "org.kde.kdeconnect.device.findmyphone").ring()
        elif cmd == "ping":
            self.plugin(dev, "ping", "org.kde.kdeconnect.device.ping").sendPing()
        elif cmd == "shareText":
            self.plugin(dev, "share", "org.kde.kdeconnect.device.share").shareText(c["text"])
        elif cmd == "shareUrl":
            self.plugin(dev, "share", "org.kde.kdeconnect.device.share").shareUrl(c["url"])

    # ── main ─────────────────────────────────────────────────────────────────
    def run(self):
        inst = self.installed()
        emit({"event": "hello", "installed": inst})
        if inst:
            self.ensure_daemon()
            self.daemon_up = False   # owner watch / refresh below sets the truth
            self.refresh_devices()
            if self.daemon_up:
                emit({"event": "daemon", "running": True})
        self.loop.run()


if __name__ == "__main__":
    try:
        Bridge().run()
    except KeyboardInterrupt:
        pass
