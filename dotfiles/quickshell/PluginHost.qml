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
// The crash guard lives in ewe-plugin: `list --json --boot` counts the starts
// that follow a CRASH (a new Quickshell crash report or a systemd automatic
// restart — a deliberate restart is neither), and the third inside a minute
// answers safeMode, on which this host loads nothing and says so with a
// notification. A start that survives a minute reports `boot-ok` (the
// budget resets).
//
// Kinds: service | panel | overlay | menu are instantiated identically — the
// plugin owns its windows and IpcHandlers. bar-widget is not instantiated
// here: Bar.qml's BarPluginSlots read `barWidgets` and Loader one per bar.
// API 3 (docs/PLUGINS.md): quick-tile / quick-page / bar-status are
// Loader-ed by Quick settings and the bar's pill from the registries
// below (`quickTiles`, `quickPages`, `barStatus`, sorted by `order`);
// dock-item is static — `dockItems` carries the manifest's icon, label and
// action and the dock renders a button. Every entry point gets the
// injected properties through `inject()` — pluginId, pluginDir, stateDir,
// settings, and per slot screen/barWindow/ink or panelOpen — but only the
// ones its root declares.
QtObject {
    id: host

    // Bump on an incompatible change to what plugins may rely on (the Theme
    // roles, the public Globals subset and the Shell singleton in
    // docs/PLUGINS.md). ewe-plugin refuses a manifest whose apiVersion it
    // does not know, so an old plugin fails at install, not at login; the
    // host still loads every version in `apiVersions` (3 is a superset of 2).
    readonly property int apiVersion: 3
    readonly property var apiVersions: [2, 3]

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
    // API 3 registries, each sorted by manifest `order` then id:
    //   quickTiles  [{ id, name, entry, span, order }]        Quick settings home grid
    //   quickPages  [{ id, name, entry, key, label, icon, order }]   rail + page stack
    //   barStatus   [{ id, name, entry, order }]              glyphs in the bar's pill
    //   dockItems   [{ id, name, icon, label, action, order }]  static dock buttons
    property var quickTiles: []
    property var quickPages: []
    property var barStatus: []
    property var dockItems: []
    // id -> plugin directory (absolute path), for `pluginDir`
    property var dirs: ({})
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

    // ── API 3 injection ───────────────────────────────────────────────────
    // Set on an entry point's root ONLY the properties it declares: pluginId,
    // pluginDir (a file:// url), stateDir (a path under
    // $XDG_STATE_HOME/ewe/plugins/<id>/, created the first time a plugin asks
    // for it), settings, plus whatever the slot passes in `extra` (screen,
    // barWindow, ink for the bar; panelOpen for Quick settings).
    readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ewe/plugins"
    property var _stateMade: ({})
    function stateDirFor(id) {
        var d = host.stateRoot + "/" + id
        if (!host._stateMade[id]) {
            var m = Object.assign({}, host._stateMade); m[id] = true; host._stateMade = m
            Quickshell.execDetached(["mkdir", "-p", d])
        }
        return d
    }
    function dirFor(id) { return host.dirs[id] || "" }
    function inject(obj, id, extra) {
        if (!obj) return
        if ("pluginId" in obj) obj.pluginId = id
        if ("pluginDir" in obj) obj.pluginDir = "file://" + host.dirFor(id)
        if ("stateDir" in obj) obj.stateDir = host.stateDirFor(id)
        if ("settings" in obj) obj.settings = host.settings[id] || ({})
        if (extra) for (var k in extra) if (k in obj) obj[k] = extra[k]
    }
    function _byOrder(a, b) { return (a.order - b.order) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0) }
    function _ord(o) { return (o && typeof o.order === "number") ? o.order : 0 }

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
            Log.warn("plugins", "SAFE MODE: the shell crashed repeatedly — no plugins loaded; enabled:", host.suspects.join(", "))
            Quickshell.execDetached(["notify-send", "-a", "ewe", "-u", "normal",
                "Plugins disabled for this session",
                "The shell crashed three times within a minute. Enabled plugins: "
                + host.suspects.join(", ") + ". Disable the culprit with ewe-plugin disable <id>."])
            host.loaded()
            return
        }
        var inst = {}, widgets = [], desk = [], pl = {}, st = {}, dirs = {}, n = 0
        var tiles = [], pages = [], status = [], dock = [], pageKeys = {}
        for (var i = 0; i < j.plugins.length; i++) {
            var p = j.plugins[i]
            if (p.widget) pl[p.id] = p.widget
            st[p.id] = p.settings || {}
            if (p.dir) dirs[p.id] = p.dir
            if (!p.enabled) continue
            if (!p.installed) {
                Log.warn("plugins", p.id, "is enabled but not installed" + (p.source ? " — ewe-plugin add " + p.source : ""))
                continue
            }
            if (!p.valid) {
                Log.warn("plugins", p.id, "skipped:", (p.problems || []).join("; "))
                continue
            }
            if (host.apiVersions.indexOf(p.apiVersion) < 0) {
                Log.warn("plugins", p.id, "skipped: apiVersion", p.apiVersion, "is not one of", host.apiVersions.join(", "))
                continue
            }
            host.dirs = dirs
            for (var k = 0; k < p.kinds.length; k++) {
                var kind = p.kinds[k]
                if (kind === "dock-item") {
                    var di = p.dockItem || {}
                    dock.push({ id: p.id, name: p.name, icon: di.icon || "icApps", label: di.label || p.name || p.id,
                                action: di.action || "", order: host._ord(di) })
                    continue
                }
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
                if (kind === "quick-tile") {
                    var qt = p.quickTile || {}
                    tiles.push({ id: p.id, name: p.name, entry: path, span: qt.span === 2 ? 2 : 1, order: host._ord(qt) })
                    continue
                }
                if (kind === "quick-page") {
                    var qp = p.quickPage || {}
                    if (!qp.key || pageKeys[qp.key]) {
                        Log.warn("plugins", p.id, "quick-page skipped:", qp.key ? "key \"" + qp.key + "\" is taken by " + pageKeys[qp.key] : "no key")
                        continue
                    }
                    pageKeys[qp.key] = p.id
                    pages.push({ id: p.id, name: p.name, entry: path, key: qp.key, label: qp.label || p.name || qp.key,
                                 icon: qp.icon || "icApps", order: host._ord(qp) })
                    continue
                }
                if (kind === "bar-status") {
                    status.push({ id: p.id, name: p.name, entry: path, order: host._ord(p.barStatus) })
                    continue
                }
                var obj = host._instantiate(p.id, kind, path)
                if (obj) {
                    host.settings = st
                    host.inject(obj, p.id)
                    if (!inst[p.id]) inst[p.id] = {}
                    inst[p.id][kind] = obj
                    n++
                }
            }
        }
        host.instances = inst
        host.placement = pl
        host.settings = st
        host.dirs = dirs
        host.barWidgets = widgets
        host.desktopWidgets = desk
        tiles.sort(host._byOrder); pages.sort(host._byOrder); status.sort(host._byOrder); dock.sort(host._byOrder)
        host.quickTiles = tiles
        host.quickPages = pages
        host.barStatus = status
        host.dockItems = dock
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
        var regs = { "quick-tile": host.quickTiles, "quick-page": host.quickPages, "bar-status": host.barStatus, "dock-item": host.dockItems }
        for (var kn in regs)
            for (var r = 0; r < regs[kn].length; r++) {
                var e = regs[kn][r]
                if (!kinds[e.id]) kinds[e.id] = []
                kinds[e.id].push(kn)
            }
        var out = []
        for (var k in kinds) out.push({ id: k, kinds: kinds[k] })
        return out
    }
}
