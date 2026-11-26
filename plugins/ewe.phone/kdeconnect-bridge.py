#!/usr/bin/env python3
"""kdeconnect-bridge.py — D-Bus bridge between kdeconnectd and the QML shell.

Quickshell has no generic QML D-Bus client, so this long-lived helper owns ALL
KDE Connect D-Bus traffic (dbus-python + GLib main loop — both ewe
dependencies, declared in manifest.json `requires`). Ships with the ewe.phone
add-on and runs from the plugin directory; the QML side (Phone.qml) runs it
as a Process and speaks newline-delimited JSON:

  stdout → events  {"event": "...", ...}   (state pushes, signal relays)
  stdin  ← commands {"cmd": "...", ...}    (pair, dismiss, send message, …)

Interfaces verified against a running kdeconnectd 26.08 with a paired phone
(device / battery / notifications / conversations — 1.1.0: conversations are
on the device object, and a message is a struct, not a dict). Every reply is
one JSON line; the bridge never crashes on a bad device — errors surface as
{"event":"error", ...}.

EWE_PHONE_NO_DAEMON=1 stops the bridge from starting kdeconnectd itself (the
nested test harness runs the shell on a private session bus: a daemon it
activated there would be a new device on the user's network).
"""

import json
import os
import shutil
import subprocess
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phone_apps   # C1 parse + C2 cache — pure stdlib, shared with the tests

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
RC_IFACE = "org.kde.kdeconnect.device.remotecommands"
SFTP_IFACE = "org.kde.kdeconnect.device.sftp"
PROPS = "org.freedesktop.DBus.Properties"

# EWE_PHONE_NO_DAEMON=1: never start kdeconnectd, not even by talking to its
# well-known name (the nested test harness on a private session bus)
NO_DAEMON = bool(os.environ.get("EWE_PHONE_NO_DAEMON"))

# pairState ints from core/pairstate.h
PAIR_NOT, PAIR_REQUESTED, PAIR_BY_PEER, PAIR_PAIRED = 0, 1, 2, 3


_emit_lock = threading.Lock()


def emit(obj):
    # threads (a CLI waiting, a folder check on a slow mount) emit too: one
    # write per line, never two lines interleaved
    line = json.dumps(obj) + "\n"
    with _emit_lock:
        sys.stdout.write(line)
        sys.stdout.flush()


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


# the folders the dock's Files tab offers: key, label, candidates under the phone's shared storage
FOLDERS = [
    ("camera", "Camera", ["DCIM/Camera"]),
    ("screenshots", "Screenshots", ["Pictures/Screenshots", "DCIM/Screenshots"]),
    ("downloads", "Downloads", ["Download", "Downloads"]),
    ("documents", "Documents", ["Documents"]),
    ("music", "Music", ["Music"]),
    ("movies", "Movies", ["Movies"]),
]


def dir_inside(path, mount):
    """A folder the phone names is only taken when it is inside the phone's own mount point."""
    if not isinstance(path, str) or not isinstance(mount, str) or not mount.startswith("/"):
        return False
    p, m = os.path.normpath(path), os.path.normpath(mount)
    return p.startswith("/") and (p == m or p.startswith(m.rstrip("/") + "/")) and ".." not in path.split("/")


def storage_folders(mount, dirs):
    """[{key,label,path}] — path "" when the phone has no such folder. May stat a
    sshfs mount: call it off the main loop."""
    roots = [(d, phone_apps.clean_name(n, "Storage")) for d, n in sorted((dirs or {}).items())
             if isinstance(n, str) and dir_inside(d, mount)]
    if not roots and mount and os.path.isdir(mount):
        roots = [(mount, "Storage")]
    if not roots:
        return []
    base = next((r for r in roots if "internal" in r[1].lower()), roots[0])[0]
    out = []
    for key, label, subs in FOLDERS:
        found = ""
        for sub in subs:
            if os.path.isdir(os.path.join(base, sub)):
                found = os.path.join(base, sub)
                break
        out.append({"key": key, "label": label, "path": found})
    out.append({"key": "storage", "label": "Internal storage", "path": base})
    for i, (d, n) in enumerate(r for r in roots if r[0] != base):
        out.append({"key": "storage%d" % (i + 2), "label": n, "path": d})
    return out


class Bridge:
    def __init__(self):
        DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SessionBus()
        self.loop = GLib.MainLoop()
        self.daemon_up = False
        self.devices = {}     # id -> dict
        self.apps_key = {}    # id -> what the last `apps` event was built from
        self.apps_sent = {}   # id -> that event's JSON (never twice the same)
        self.was_paired = set()

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
        sub(self.on_commands, dbus_interface=RC_IFACE, signal_name="commandsChanged", path_keyword="path")
        sub(self.on_message, dbus_interface=CONV_IFACE, signal_name="conversationCreated", path_keyword="path")
        sub(self.on_message, dbus_interface=CONV_IFACE, signal_name="conversationUpdated", path_keyword="path")
        sub(self.on_conv_removed, dbus_interface=CONV_IFACE, signal_name="conversationRemoved", path_keyword="path")
        # daemon appearing/disappearing (restart, first activation)
        self.bus.watch_name_owner(SERVICE, self.on_owner_changed)

        GLib.io_add_watch(sys.stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.on_stdin)

    # ── the daemon's objects ─────────────────────────────────────────────────
    def obj(self, path):
        """A proxy for one kdeconnectd object. A method call on the well-known
        name AUTO-ACTIVATES kdeconnectd (the bus does it, whatever ensure_daemon
        decided), so in no-daemon mode an unowned name is an error instead."""
        if NO_DAEMON and not self.bus.name_has_owner(SERVICE):
            raise dbus.DBusException("kdeconnectd is not running (EWE_PHONE_NO_DAEMON)")
        return self.bus.get_object(SERVICE, path)

    # ── daemon lifecycle ────────────────────────────────────────────────────
    def ensure_daemon(self):
        try:
            if self.bus.name_has_owner(SERVICE):
                return True
        except dbus.DBusException:
            return False
        if NO_DAEMON:
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
            o = self.obj(path)
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
            daemon = dbus.Interface(self.obj(DAEMON_PATH), DAEMON_IFACE)
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
        for i in list(self.devices):
            self.sync_apps(i)

    def push_devices(self):
        emit({"event": "devices", "list": sorted(self.devices.values(), key=lambda d: d["name"].lower())})

    def refresh_one(self, dev_id):
        d = self.read_device(dev_id)
        if d:
            self.devices[dev_id] = d
        else:
            self.devices.pop(dev_id, None)
        self.push_devices()
        self.sync_apps(dev_id)

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
            o = self.obj(self.dev_path(dev_id) + "/notifications")
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
        """One message as the QML side wants it. The daemon sends a STRUCT in
        a variant — (event, body, [(address,)…], date, type, read, thread id,
        uid, sub id, [(part id, mime, base64 thumbnail, unique id)…]) —
        which dbus-python hands over as a sequence; a dict with the same
        names is taken too (older builds, the tests)."""
        m = plain(m)
        if isinstance(m, (list, tuple)):
            if len(m) < 9:
                return None
            m = {"event": m[0], "body": m[1], "addresses": m[2], "date": m[3], "type": m[4],
                 "read": m[5], "thread_id": m[6], "u_id": m[7],
                 "attachments": m[9] if len(m) > 9 else []}
        if not isinstance(m, dict):
            return None
        addrs = []
        for a in (m.get("addresses") or []):
            if isinstance(a, dict) and a.get("address"):
                addrs.append(str(a["address"]))
            elif isinstance(a, (list, tuple)) and a and isinstance(a[0], str) and a[0]:
                addrs.append(a[0])          # the struct (address,)
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
        # the conversations interface lives on the DEVICE object: there is no
        # /conversations child (kdeconnect 26.08, `busctl --user introspect`)
        o = self.obj(self.dev_path(dev_id))
        return dbus.Interface(o, CONV_IFACE)

    def on_message(self, msg, path=""):
        m = self.norm_message(msg)
        if m:
            emit({"event": "message", "deviceId": self.id_from_path(path), "msg": m})

    def on_conv_removed(self, conv_id, path=""):
        emit({"event": "conversationRemoved", "deviceId": self.id_from_path(path), "threadId": int(plain(conv_id))})

    # ── the phone's apps (C1 in, C2 out) ─────────────────────────────────────
    def read_commands(self, dev_id):
        """`remotecommands.commands` as bytes, or None when the device has no
        such object (plugin off, not loaded yet)."""
        try:
            o = self.obj(self.dev_path(dev_id) + "/remotecommands")
            return phone_apps.to_bytes(dbus.Interface(o, PROPS).Get(RC_IFACE, "commands", byte_arrays=True))
        except dbus.DBusException:
            return None

    def on_commands(self, *args, path=""):
        self.sync_apps(self.id_from_path(path))

    def sync_apps(self, dev_id, force=False):
        """Read the phone's list (when it is in reach), keep the cache, tell
        QML. A phone that is away, or has not answered yet, is shown from the
        cache; a paired phone that never ran ewe Mobile has `ewe: false`."""
        base = phone_apps.cache_base()
        d = self.devices.get(dev_id)
        if not d or not d.get("isPaired"):
            self.apps_key.pop(dev_id, None)
            self.apps_sent.pop(dev_id, None)
            if d is not None and dev_id in self.was_paired:
                # unpaired: its apps and icons go (C4 does the same for launcher entries)
                self.was_paired.discard(dev_id)
                phone_apps.remove_cache(base, dev_id)
                emit({"event": "apps", "deviceId": dev_id, "ewe": False, "cached": False, "loading": False,
                      "updated": 0, "apps": [], "dropped": 0})
            return
        self.was_paired.add(dev_id)
        reachable = bool(d.get("isReachable"))
        raw = self.read_commands(dev_id) if reachable else None
        key = (reachable, d.get("name"), raw)
        if not force and self.apps_key.get(dev_id) == key:
            return
        self.apps_key[dev_id] = key
        kind, data = ("none", None) if raw is None else phone_apps.parse_commands(raw)
        ev = {"event": "apps", "deviceId": dev_id, "ewe": False, "cached": False, "loading": False,
              "updated": 0, "apps": [], "dropped": 0}
        try:
            if kind == "ewe":
                doc, _ = phone_apps.write_cache(base, dev_id, d.get("name", ""), data["apps"])
                ev.update(ewe=True, updated=doc["updated"], apps=doc["apps"], dropped=data["dropped"])
            elif kind == "other" and reachable:
                pass                                           # a phone with someone else's list: stock KDE Connect
            else:
                # away, or reachable and silent so far: what we kept
                doc = phone_apps.read_cache(base, dev_id)
                if doc:
                    ev.update(ewe=True, cached=True, loading=reachable, updated=doc["updated"], apps=doc["apps"])
        except (OSError, ValueError) as e:
            emit({"event": "error", "cmd": "apps", "error": "cache: %s" % e})
        sig = json.dumps(ev, sort_keys=True)
        if force or self.apps_sent.get(dev_id) != sig:
            self.apps_sent[dev_id] = sig
            emit(ev)

    def sync_all_apps(self, force=False):
        for i in list(self.devices):
            self.sync_apps(i, force)

    # ── tools on this computer ───────────────────────────────────────────────
    def tools(self):
        emit({"event": "tools", "eweMobile": shutil.which("ewe-mobile") is not None,
              "eweFiles": shutil.which("ewe-files-app") is not None})

    # ── opening an app, mirroring, files ─────────────────────────────────────
    def trigger(self, dev_id, key):
        """C1: triggerCommand(<package>) starts it on the phone; ewe:refresh asks for the list."""
        self.plugin(dev_id, "remotecommands", RC_IFACE).triggerCommand(key)

    def run_cli(self, args, what, extra):
        """C3: `ewe-mobile …` answers one JSON line and exits 0; read it off the main loop."""
        def work():
            ev = dict(extra, event=what, ok=False, error="", message="")
            try:
                r = subprocess.run(args, capture_output=True, text=True, timeout=25, stdin=subprocess.DEVNULL)
                j = None
                for line in reversed(r.stdout.strip().splitlines()):
                    try:
                        j = json.loads(line)
                        break
                    except ValueError:
                        continue
                if isinstance(j, dict):
                    ev["ok"] = j.get("ok") is True
                    ev["error"] = phone_apps.clean_name(j.get("error", ""))[:40]
                    ev["message"] = phone_apps.clean_name(j.get("message", ""))
                else:
                    ev["ok"] = r.returncode == 0
                    ev["error"] = "" if ev["ok"] else "failed"
            except (OSError, subprocess.SubprocessError) as e:
                ev["error"], ev["message"] = "failed", str(e)
            emit(ev)
        threading.Thread(target=work, daemon=True).start()

    def open_app(self, dev_id, pkg, where):
        if not phone_apps.package_ok(pkg):
            raise ValueError("not a package name")
        exe = shutil.which("ewe-mobile")
        if where == "phone" or not exe:
            self.trigger(dev_id, pkg)
            emit({"event": "openApp", "deviceId": dev_id, "package": pkg, "ok": True, "error": "", "message": "", "via": "phone"})
            return
        args = [exe, "--open-app", pkg, "--device", dev_id] + (["--here"] if where == "here" else [])
        self.run_cli(args, "openApp", {"deviceId": dev_id, "package": pkg, "via": where})

    def mirror(self, dev_id):
        exe = shutil.which("ewe-mobile")
        if not exe:
            emit({"event": "mirror", "deviceId": dev_id, "ok": False, "error": "no-ewe-mobile",
                  "message": "ewe Mobile is not installed on this computer."})
            return
        self.run_cli([exe, "--screen", "--device", dev_id], "mirror", {"deviceId": dev_id})

    # ── the phone's storage (sftp) ───────────────────────────────────────────
    def storage_event(self, dev_id, state, **kw):
        emit(dict({"event": "storage", "deviceId": dev_id, "state": state, "folders": [], "mount": "",
                   "error": "", "message": ""}, **kw))

    def away(self, dev_id):
        d = self.devices.get(dev_id)
        return not d or not d.get("isReachable") or not d.get("isPaired")

    def mount(self, dev_id):
        if self.away(dev_id):
            self.storage_event(dev_id, "error", error="away",
                               message="Your phone is out of reach. Wake it and put it on this network, then try again.")
            return
        sftp = self.plugin(dev_id, "sftp", SFTP_IFACE)
        self.storage_event(dev_id, "mounting")

        def ok(res):
            if res:
                self.resolve_storage(dev_id)
                return
            try:
                why = phone_apps.clean_name(str(plain(sftp.getMountError())))
            except dbus.DBusException:
                why = ""
            self.storage_event(dev_id, "error", error="failed",
                               message=why or "Your phone did not answer. Unlock it, keep it on this network, then try again.")

        def bad(e):
            self.storage_event(dev_id, "error", error="failed",
                               message="Your phone did not answer. Unlock it, keep it on this network, then try again.")
        sftp.mountAndWait(reply_handler=ok, error_handler=bad, timeout=45)

    def storage(self, dev_id):
        """Where the phone's storage stands now, without mounting it."""
        if self.away(dev_id):
            self.storage_event(dev_id, "idle")
            return
        try:
            sftp = self.plugin(dev_id, "sftp", SFTP_IFACE)
            if bool(sftp.isMounted()):
                self.resolve_storage(dev_id)
                return
        except dbus.DBusException:
            pass
        self.storage_event(dev_id, "idle")

    def resolve_storage(self, dev_id):
        sftp = self.plugin(dev_id, "sftp", SFTP_IFACE)
        mount = str(plain(sftp.mountPoint()))
        dirs = plain(sftp.getDirectories())
        self.finish_storage(dev_id, mount, dirs)

    def finish_storage(self, dev_id, mount, dirs):
        # the folder checks stat the sshfs mount: a phone that went away would
        # hang them — a thread, so the bridge's loop never waits on a phone
        def work():
            try:
                folders = storage_folders(mount, dirs)
            except OSError:
                folders = []
            if folders:
                self.storage_event(dev_id, "mounted", mount=mount, folders=folders)
            else:
                self.storage_event(dev_id, "error", error="failed",
                                   message="The phone's storage is connected but shows no folders. Unlock the phone and try again.")
        threading.Thread(target=work, daemon=True).start()

    # ── commands from QML ────────────────────────────────────────────────────
    def on_stdin(self, source, condition):
        # read the fd itself and split lines here: sys.stdin.readline() takes one
        # line and leaves the rest in Python's buffer, where the watch (which
        # only sees the fd) never fires for them — a burst of commands stalled
        if not hasattr(self, "inbuf"):
            self.inbuf = b""
        try:
            data = os.read(sys.stdin.fileno(), 65536) if condition & GLib.IO_IN else b""
        except OSError:
            data = b""
        if data == b"":
            self.loop.quit()
            return False
        self.inbuf += data
        while b"\n" in self.inbuf:
            line, self.inbuf = self.inbuf.split(b"\n", 1)
            self.command_line(line)
        if len(self.inbuf) > 1 << 20:
            self.inbuf = b""                  # a line that never ends is not a command
        return True

    def command_line(self, raw):
        try:
            c = json.loads(raw.decode("utf-8", "replace"))
            if not isinstance(c, dict):
                return
        except ValueError:
            return
        try:
            self.handle(c)
        except dbus.DBusException as e:
            emit({"event": "error", "cmd": c.get("cmd", "?"), "error": e.get_dbus_message()})
        except Exception as e:  # never die on a bad command
            emit({"event": "error", "cmd": c.get("cmd", "?"), "error": str(e)})

    def checked(self, dev_id):
        """A device id that goes into an object path: what kdeconnectd writes, nothing else."""
        if not phone_apps.DEV_RE.match(dev_id or ""):
            raise ValueError("bad device id")
        return dev_id

    def dev_iface(self, dev_id):
        return dbus.Interface(self.obj(self.dev_path(dev_id)), DEV_IFACE)

    def plugin(self, dev_id, sub, iface):
        return dbus.Interface(self.obj(self.dev_path(dev_id) + "/" + sub), iface)

    def handle(self, c):
        cmd, dev = c.get("cmd", ""), c.get("deviceId") or c.get("device") or ""
        if cmd in ("openApp", "refreshApps", "mirror", "mount", "storage", "apps") and cmd != "apps" \
                and not isinstance(dev, str):
            raise ValueError("bad device")
        if cmd == "refresh":
            if self.ensure_daemon():
                try:
                    dbus.Interface(self.obj(DAEMON_PATH), DAEMON_IFACE).forceOnNetworkChange()
                except dbus.DBusException:
                    pass
            self.tools()
            self.refresh_devices()
            self.sync_all_apps(force=True)
        elif cmd == "apps":
            self.sync_all_apps(force=True)
        elif cmd == "openApp":
            where = c.get("where") if c.get("where") in ("here", "phone", "auto") else "auto"
            self.open_app(self.checked(dev), str(c.get("package", "")), where)
        elif cmd == "refreshApps":
            self.trigger(self.checked(dev), "ewe:refresh")
        elif cmd == "mirror":
            self.mirror(self.checked(dev))
        elif cmd == "mount":
            self.mount(self.checked(dev))
        elif cmd == "storage":
            self.storage(self.checked(dev))
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
            o = self.obj(self.dev_path(dev) + "/notifications/" + c["id"])
            dbus.Interface(o, NOTIF_OBJ_IFACE).dismiss()
        elif cmd == "replyNotif":
            self.plugin(dev, "notifications", NOTIF_IFACE).sendReply(c["replyId"], c["text"])
        elif cmd == "requestConversations":
            conv = self.conv_iface(dev)
            # what the daemon already holds first: asked a second time it only
            # says "loaded" per thread and sends no message again
            for msg in conv.activeConversations():
                m = self.norm_message(msg)
                if m:
                    emit({"event": "message", "deviceId": dev, "msg": m})
            conv.requestAllConversationThreads()
        elif cmd == "requestConversation":
            self.conv_iface(dev).requestConversation(
                dbus.Int64(int(c["threadId"])), dbus.Int32(int(c.get("start", 0))), dbus.Int32(int(c.get("end", 30))))
        elif cmd == "sendMessage":
            self.conv_iface(dev).replyToConversation(
                dbus.Int64(int(c["threadId"])), c["text"], dbus.Array([], signature="v"))
        elif cmd == "sendToAddress":
            # a recipient is the struct (address,) in a variant — the daemon
            # reads it with qdbus_cast<ConversationAddress>, which a dict is not
            addr = dbus.Struct((dbus.String(c["address"]),), signature="s", variant_level=1)
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
        self.tools()
        if inst:
            self.ensure_daemon()
            self.daemon_up = False   # owner watch / refresh below sets the truth
            self.refresh_devices()
            if self.daemon_up:
                emit({"event": "daemon", "running": True})
        self.loop.run()


class FixtureBridge(Bridge):
    """EWE_PHONE_FIXTURE=<file.json>: the plugin's popup without a phone or a bus.

    {"eweMobile": true, "eweFiles": true,
     "devices": [{"id": "fix1", "name": "Pixel 10 Pro XL", "isReachable": true, "batteryCharge": 72}],
     "commands": {"fix1": <what the phone sends: the C1 object, or its JSON as a string>},
     "storage":  {"fix1": {"mode": "ok"|"error"|"away", "root": "<a directory standing in for the mount>"}}}

    The commands go through the same parse + cache code as a real phone's; the
    file is re-read when it changes, so a state can be edited while the shell runs."""

    def __init__(self, path):
        self.path = path
        self.loop = GLib.MainLoop()
        self.daemon_up = True
        self.devices, self.apps_key, self.apps_sent, self.was_paired = {}, {}, {}, set()
        self.fx, self.mtime = {}, 0
        self.mounted_fx = set()
        GLib.io_add_watch(sys.stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.on_stdin)
        GLib.timeout_add(1000, self.poll)

    def load(self):
        try:
            st = os.stat(self.path)
            if st.st_mtime_ns == self.mtime:
                return False
            with open(self.path) as f:
                self.fx = json.load(f)
            self.mtime = st.st_mtime_ns
        except (OSError, ValueError):
            return False
        devs = {}
        for d in self.fx.get("devices", []):
            devs[d["id"]] = {"id": d["id"], "name": d.get("name", d["id"]), "type": "phone",
                             "isReachable": d.get("isReachable", True), "isPaired": d.get("isPaired", True),
                             "pairState": 3, "pairRequestedByPeer": False, "plugins": [],
                             "batteryCharge": d.get("batteryCharge", -1), "isCharging": d.get("isCharging", False)}
        self.devices = devs
        return True

    def poll(self):
        if self.load():
            self.mounted_fx.clear()                # a new scenario starts unmounted
            self.push_devices()
            self.sync_all_apps(force=True)
            for i in list(self.devices):
                self.storage_event(i, "idle")
        return True

    def read_commands(self, dev_id):
        v = self.fx.get("commands", {}).get(dev_id)
        if v is None:
            return None
        return phone_apps.to_bytes(v if isinstance(v, str) else json.dumps(v))

    def trigger(self, dev_id, key):
        emit({"event": "fixture", "triggered": key, "deviceId": dev_id})

    def run_cli(self, args, what, extra):
        emit(dict(extra, event=what, ok=True, error="", message="fixture: " + " ".join(args[1:])))

    def mount(self, dev_id):
        cfg = self.fx.get("storage", {}).get(dev_id, {"mode": "ok"})
        if self.away(dev_id) or cfg.get("mode") == "away":
            self.storage_event(dev_id, "error", error="away",
                               message="Your phone is out of reach. Wake it and put it on this network, then try again.")
            return
        self.storage_event(dev_id, "mounting")

        def done():
            if cfg.get("mode") == "error":
                self.storage_event(dev_id, "error", error="failed",
                                   message="Your phone did not answer. Unlock it, keep it on this network, then try again.")
            else:
                self.mounted_fx.add(dev_id)
                self.resolve_fixture(dev_id)
            return False
        GLib.timeout_add(900, done)

    def storage(self, dev_id):
        if dev_id in self.mounted_fx:
            self.resolve_fixture(dev_id)
        else:
            self.storage_event(dev_id, "idle")

    def resolve_fixture(self, dev_id):
        root = self.fx.get("storage", {}).get(dev_id, {}).get("root", "/nonexistent")
        self.finish_storage(dev_id, root, {os.path.join(root, "storage/emulated/0"): "Internal shared storage"})

    def push_notifications(self, dev_id):
        emit({"event": "notifications", "deviceId": dev_id, "list": []})

    def handle(self, c):
        cmd = c.get("cmd", "")
        if cmd == "refresh":
            self.tools()
            self.push_devices()
            self.sync_all_apps(force=True)
        elif cmd in ("pair", "unpair", "acceptPair", "cancelPair", "requestConversations", "requestConversation",
                     "sendMessage", "sendToAddress", "ring", "ping", "shareText", "shareUrl", "dismiss", "replyNotif"):
            pass                                   # nothing to talk to
        else:
            super().handle(c)

    def run(self):
        emit({"event": "hello", "installed": True})
        self.tools()
        emit({"event": "daemon", "running": True})
        self.load()
        self.push_devices()
        self.sync_all_apps(force=True)
        self.loop.run()

    def tools(self):
        emit({"event": "tools", "eweMobile": bool(self.fx.get("eweMobile", True)),
              "eweFiles": bool(self.fx.get("eweFiles", True))})


if __name__ == "__main__":
    try:
        fx = os.environ.get("EWE_PHONE_FIXTURE")
        (FixtureBridge(fx) if fx else Bridge()).run()
    except KeyboardInterrupt:
        pass
