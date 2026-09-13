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
// that compiles and then crashes takes the shell down with it — the crash
// guard (a plugins-off boot after repeated respawns) is what makes that
// survivable.
//
// Kinds: service | panel | overlay | menu are instantiated identically — the
// plugin owns its windows and IpcHandlers. bar-widget is not instantiated
// here; the bar's plugin slots (Bar.qml, ewe 0.14) read `barWidgets`.
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
    // bar-widget entries of enabled, valid plugins, for Bar.qml's slots:
    // [{ id, name, entry (absolute path), barWidget }]
    property var barWidgets: []
    property bool scanned: false
    signal loaded()

    function start() {
        if (host.scanned || host._scan.running) return
        host._scan.running = true
    }

    property Process _scan: Process {
        command: [host.tool, "list", "--json"]
        stdout: StdioCollector { onStreamFinished: host._onList(this.text) }
        stderr: StdioCollector {
            onStreamFinished: { if (this.text.trim()) Log.warn("plugins", "ewe-plugin:", this.text.trim()) }
        }
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
        var inst = {}, widgets = [], n = 0
        for (var i = 0; i < j.plugins.length; i++) {
            var p = j.plugins[i]
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
                var obj = host._instantiate(p.id, kind, path)
                if (obj) {
                    if (!inst[p.id]) inst[p.id] = {}
                    inst[p.id][kind] = obj
                    n++
                }
            }
        }
        host.instances = inst
        host.barWidgets = widgets
        Log.info("plugins", n + " entry point(s) loaded from " + Object.keys(inst).length + " plugin(s)")
        host.loaded()
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
        var out = []
        for (var id in host.instances) out.push({ id: id, kinds: Object.keys(host.instances[id]) })
        return out
    }
}
