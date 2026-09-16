pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// PluginHost — third-party shell plugins (bin/ewe-plugin, docs/PLUGINS.md).
//
// A plugin is a directory under ~/.config/ewe/plugins/<id>/ with a
// manifest.json naming one QML entry point per kind. This singleton asks
// `ewe-plugin list --json` what is installed and enabled — ONE process at
// startup, the same tool the user drives, so the manifest rules live in one
// place — and instantiates each enabled entry point by absolute path. A file
// loaded that way still resolves `import qs` (verified on Quickshell 0.3.1),
// so a plugin uses Theme and Globals exactly like a first-party component.
//
// The host does nothing else on purpose: no sandbox (impossible inside one
// QML engine), no API object to inject, no hot reload (ewe-plugin restarts
// ewe.service). A plugin that fails to compile is logged and skipped; one
// that compiles and then crashes takes the shell down with it, and
// ewe.service relaunches it a second later — a login loop with no desktop.
// The crash guard lives in ewe-plugin: `list --json --boot` counts starts,
// and the third inside a minute answers safeMode, on which this host loads
// nothing and says so with a notification. A start that survives a minute
// reports `boot-ok` (the budget resets).
//
// Kinds: service | panel | overlay | menu are instantiated identically — the
// plugin owns its windows and IpcHandlers. bar-widget is not instantiated
// here: Bar.qml's BarPluginSlots read `barWidgets` and Loader one per bar.
QtObject {
    id: host

    // Bump on an incompatible change to what plugins may rely on (the Theme
    // roles, the public Globals subset in docs/PLUGINS.md). ewe-plugin refuses
    // a manifest whose apiVersion differs, so an old plugin fails at install,
    // not at login.
    readonly property int apiVersion: 1

    // Same idiom as Globals.eweConf: the payload's bin/, reached through the
    // ~/.config/quickshell symlink (the kernel resolves the link before the
    // `..`). EWE_PLUGIN_TOOL is the dev override the run-ewe driver exports so
    // a nested shell exercises the checkout's tool, not the installed one.
    readonly property string tool: Quickshell.env("EWE_PLUGIN_TOOL") || (Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-plugin")

    // Everything `ewe-plugin list --json` reported — valid or not, on or off.
    property var plugins: []
    // id -> { kind -> instance } for what actually got instantiated.
    property var instances: ({})
    // bar-widget entries of enabled, valid plugins, for BarPluginSlots:
    // [{ id, name, entry (absolute path), barWidget: { defaultSection } }]
    property var barWidgets: []
    // desktop-widget entries, for DesktopWidgets: [{ id, name, entry }] —
    // WHERE each sits is `placement[id]` ({x, y, output, layer, visible}),
    // kept apart so a drag or `ewe-plugin place` moves it without a reload
    property var desktopWidgets: []
    property var placement: ({})
    // id -> {key: value}: what the plugin declared in manifest.json under the
    // user's values (ewe.conf plugins.settings.<id>). Handed to every entry
    // point that has a `settings` property, live on `reload`.
    property var settings: ({})
    property bool scanned: false
    // true when this start was the third inside a minute: nothing loaded
    property bool safeMode: false
    property var suspects: []
    signal loaded()

    function start() {
        if (host.scanned || host._scan.running) return
        host._scan.running = true
    }

    property Process _scan: Process {
        command: [host.tool, "list", "--json", "--boot"]
        stdout: StdioCollector { onStreamFinished: host._onList(this.text) }
        stderr: StdioCollector {
            onStreamFinished: { if (this.text.trim()) Log.warn("plugins", "ewe-plugin:", this.text.trim()) }
        }
    }

    // `qs ipc call plugins reload` — after `ewe-plugin place` / `set`: the
    // placement and settings maps are re-read and pushed into the live
    // instances. Enabling/disabling still restarts the shell (no hot reload).
    function reload() { if (!host._reload.running) host._reload.running = true }
    property Process _reload: Process {
        command: [host.tool, "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) {}
                if (!j || !Array.isArray(j.plugins)) return
                var pl = {}, st = {}
                for (var i = 0; i < j.plugins.length; i++) {
                    var p = j.plugins[i]
                    if (p.widget) pl[p.id] = p.widget
                    st[p.id] = p.settings || {}
                }
                host.placement = pl
                host.settings = st
                for (var id in host.instances)
                    for (var kind in host.instances[id]) host._giveSettings(host.instances[id][kind], id)
                Log.debug("plugins", "reloaded placement + settings")
            }
        }
    }
    function _giveSettings(obj, id) {
        if (obj && ("settings" in obj)) obj.settings = host.settings[id] || ({})
    }
    function settingsFor(id) { return host.settings[id] || ({}) }

    // a drag in arrange mode, or a Komble control: remember in memory now
    // (the widget follows the binding), persist through ewe-plugin, which
    // pokes `reload` back at us — a no-op round trip
    function placeWidget(id, x, y) {
        var pl = Object.assign({}, host.placement)
        pl[id] = Object.assign({}, pl[id] || {}, { x: Math.round(x), y: Math.round(y) })
        host.placement = pl
        Quickshell.execDetached([host.tool, "place", id, "--x", String(Math.round(x)), "--y", String(Math.round(y))])
    }
    function setWidgetLayer(id, layer) {
        var pl = Object.assign({}, host.placement)
        pl[id] = Object.assign({}, pl[id] || {}, { layer: layer })
        host.placement = pl
        Quickshell.execDetached([host.tool, "place", id, "--layer", layer])
    }
    function setWidgetVisible(id, on) {
        var pl = Object.assign({}, host.placement)
        pl[id] = Object.assign({}, pl[id] || {}, { visible: !!on })
        host.placement = pl
        Quickshell.execDetached([host.tool, "place", id, "--visible", on ? "on" : "off"])
    }

    function _onList(text) {
        host.scanned = true
        var j = null
        try { j = JSON.parse(text) } catch (e) {}
        if (!j || !j.ok || !Array.isArray(j.plugins)) {
            // an absent tool is a fresh tarball deploy without bin/ — not an
            // error worth a login-time warning unless it said something
            if (text.trim()) Log.warn("plugins", "ewe-plugin list --json returned nothing usable")
            host.loaded()
            return
        }
        host.plugins = j.plugins
        if (j.safeMode) {
            host.safeMode = true
            host.suspects = j.suspects || []
            Log.warn("plugins", "SAFE MODE: the shell restarted repeatedly — no plugins loaded; enabled:", host.suspects.join(", "))
            Quickshell.execDetached(["notify-send", "-a", "ewe", "-u", "normal",
                "Plugins disabled for this session",
                "The shell restarted three times within a minute. Enabled plugins: "
                + host.suspects.join(", ") + ". Disable the culprit with ewe-plugin disable <id>."])
            host.loaded()
            return
        }
        var inst = {}, widgets = [], desk = [], pl = {}, st = {}, n = 0
        for (var i = 0; i < j.plugins.length; i++) {
            var p = j.plugins[i]
            if (p.widget) pl[p.id] = p.widget
            st[p.id] = p.settings || {}
            if (!p.enabled) continue
            if (!p.installed) {
                Log.warn("plugins", p.id, "is enabled but not installed" + (p.source ? " — ewe-plugin add " + p.source : ""))
                continue
            }
            if (!p.valid) {
                Log.warn("plugins", p.id, "skipped:", (p.problems || []).join("; "))
                continue
            }
            for (var k = 0; k < p.kinds.length; k++) {
                var kind = p.kinds[k]
                var rel = p.entryPoints[kind]
                if (!rel) continue
                var path = p.dir + "/" + rel
                if (kind === "bar-widget") {
                    widgets.push({ id: p.id, name: p.name, entry: path, barWidget: p.barWidget || {} })
                    continue
                }
                if (kind === "desktop-widget") {
                    desk.push({ id: p.id, name: p.name, entry: path })
                    continue
                }
                var obj = host._instantiate(p.id, kind, path)
                if (obj) {
                    if ("settings" in obj) obj.settings = st[p.id] || ({})
                    if (!inst[p.id]) inst[p.id] = {}
                    inst[p.id][kind] = obj
                    n++
                }
            }
        }
        host.instances = inst
        host.placement = pl
        host.settings = st
        host.barWidgets = widgets
        host.desktopWidgets = desk
        Log.info("plugins", n + " entry point(s) loaded from " + Object.keys(inst).length + " plugin(s)")
        host._settle.start()
        host.loaded()
    }

    // a start that stays up this long was not a crash loop: reset the budget
    property Timer _settle: Timer {
        interval: 60000
        onTriggered: Quickshell.execDetached([host.tool, "boot-ok"])
    }

    // Instances hang off a Scope rather than this QtObject: PanelWindows and
    // IpcHandlers get reparented at creation, and a Scope is what shell.qml's
    // own lazy panels are created under.
    property Scope _root: Scope {}

    function _instantiate(id, kind, path) {
        var c = Qt.createComponent("file://" + path)
        if (c.status === Component.Error) {
            Log.warn("plugins", id + "/" + kind + ":", c.errorString().trim())
            return null
        }
        if (c.status !== Component.Ready) {
            Log.warn("plugins", id + "/" + kind + ": component not ready (status " + c.status + ")")
            return null
        }
        var obj = c.createObject(host._root)
        if (!obj) {
            Log.warn("plugins", id + "/" + kind + ": createObject returned null")
            return null
        }
        Log.debug("plugins", "loaded", id, kind, path)
        return obj
    }

    // What the `plugins` IPC target reports: the ids and kinds that are live —
    // which can be fewer than ewe-plugin enabled (a compile error is skipped).
    function summary() {
        var kinds = {}
        for (var id in host.instances) kinds[id] = Object.keys(host.instances[id])
        for (var i = 0; i < host.barWidgets.length; i++) {
            var w = host.barWidgets[i]
            if (!kinds[w.id]) kinds[w.id] = []
            kinds[w.id].push("bar-widget")
        }
        for (var d = 0; d < host.desktopWidgets.length; d++) {
            var dw = host.desktopWidgets[d]
            if (!kinds[dw.id]) kinds[dw.id] = []
            kinds[dw.id].push("desktop-widget")
        }
        var out = []
        for (var k in kinds) out.push({ id: k, kinds: kinds[k] })
        return out
    }
}
