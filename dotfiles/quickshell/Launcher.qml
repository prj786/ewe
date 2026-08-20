import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Launcher — a centered, frosted app launcher with fuzzy search.
// Toggled via IPC:  qs ipc call applauncher toggle   (bound to Super+D).
Scope {
    id: root

    property bool opened: false
    property string query: ""
    property int selected: 0
    readonly property string home: Quickshell.env("HOME") || ""

    // apps (in-memory, instant) + files/folders (plocate, debounced) → merged list
    property var appResults: filterApps(query)
    property var fileResults: []
    property string fileQuery: ""
    property var results: mergeResults()

    function toggle() { opened = !opened }
    function hide()   { opened = false }

    // clear the INPUT too — resetting only `query` leaves the old text on
    // screen while the results are unfiltered (stale-search bug on reopen)
    // `held` keeps the window mapped through the close fade — the compositor's
    // layer fade is noanim'd for this namespace, so the QML must play it (set
    // on OPEN so no signal-order race can unmap early; see Overview.qml)
    property bool held: false
    property Timer _closeHold: Timer { interval: Math.max(1, Theme.durBase + 60); onTriggered: root.held = false }
    onOpenedChanged: {
        if (opened) { _closeHold.stop(); held = true; query = ""; input.text = ""; selected = 0; fileResults = [] }
        else _closeHold.restart()
    }
    onResultsChanged: if (selected >= results.length) selected = Math.max(0, results.length - 1)
    onQueryChanged: {
        var q = query.trim()
        if (q.length >= 2) fileDebounce.restart()
        else { fileDebounce.stop(); fileProc.running = false; fileResults = [] }
    }

    IpcHandler {
        target: "applauncher"
        function toggle(): void { root.toggle() }
        function show(): void { root.opened = true }
        function hide(): void { root.opened = false }
    }

    // ── file/folder search (plocate, basename match, home-scoped, noise-filtered) ──
    // $1 = query; emits "<d|f>\t<abs-path>" per line so the icon can be a folder/file.
    readonly property string fileScript: "plocate -i -b -l 2000 -- \"$1\" 2>/dev/null | grep \"^$HOME/\" | grep -vE \"/(\\.cache|\\.git|\\.cargo|\\.rustup|\\.npm|\\.gradle|\\.mozilla|node_modules)/|/\\.var/app/[^/]+/cache/|/\\.local/share/Trash/\" | head -25 | while IFS= read -r p; do if [ -d \"$p\" ]; then printf \"d\\t%s\\n\" \"$p\"; else printf \"f\\t%s\\n\" \"$p\"; fi; done"

    Timer { id: fileDebounce; interval: 140; onTriggered: root.runFileSearch() }

    Process {
        id: fileProc
        stdout: StdioCollector {
            onStreamFinished: {
                var q = root.fileQuery.toLowerCase()
                var lines = this.text.split("\n"), arr = []
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i]; if (!ln) continue
                    var t = ln.indexOf("\t"); if (t < 0) continue
                    var isDir = ln.charAt(0) === "d"
                    var path = ln.slice(t + 1)
                    var slash = path.lastIndexOf("/")
                    var nm = path.slice(slash + 1)
                    var dir = path.slice(0, slash)
                    var disp = (root.home && dir.indexOf(root.home) === 0) ? "~" + dir.slice(root.home.length) : dir
                    arr.push({ type: "file", isDir: isDir, path: path, name: nm, sub: disp,
                               iconSource: Quickshell.iconPath(isDir ? "folder" : "text-x-generic", isDir ? "folder" : "application-x-zerosize") })
                }
                // basename-prefix matches first, then shortest name
                arr.sort(function (a, b) {
                    var ap = a.name.toLowerCase().indexOf(q) === 0 ? 0 : 1
                    var bp = b.name.toLowerCase().indexOf(q) === 0 ? 0 : 1
                    if (ap !== bp) return ap - bp
                    return a.name.length - b.name.length
                })
                root.fileResults = arr
            }
        }
    }

    // ── fuzzy ranking ─────────────────────────────────────────────────────
    function filterApps(q) {
        var all = DesktopEntries.applications.values
        var vis = []
        for (var i = 0; i < all.length; i++)
            if (!all[i].noDisplay) vis.push(all[i])

        q = q.trim().toLowerCase()
        if (q.length === 0) {
            vis.sort(function (a, b) {
                return (a.name || "").toLowerCase() < (b.name || "").toLowerCase() ? -1 : 1
            })
            return vis
        }
        var scored = []
        for (var j = 0; j < vis.length; j++) {
            var s = scoreEntry(vis[j], q)
            if (s > 0) scored.push({ e: vis[j], s: s, n: (vis[j].name || "").toLowerCase() })
        }
        scored.sort(function (a, b) { return b.s - a.s || (a.n < b.n ? -1 : 1) })
        var out = []
        for (var k = 0; k < scored.length; k++) out.push(scored[k].e)
        return out
    }

    function scoreEntry(e, q) {
        var name = (e.name || "").toLowerCase()
        var gen  = (e.genericName || "").toLowerCase()
        var com  = (e.comment || "").toLowerCase()
        if (name === q) return 1000
        if (name.indexOf(q) === 0) return 850
        if (name.indexOf(" " + q) >= 0) return 700      // word start
        if (name.indexOf(q) >= 0) return 500
        if (gen.indexOf(q) >= 0) return 280
        if (com.indexOf(q) >= 0) return 120
        return 0
    }

    // ── merge apps + files into one normalized result list ────────────────
    // each item: { type:"app"|"file", name, sub, iconSource, entry?|path?, isDir? }
    // synthetic in-shell actions (e.g. open Settings) surfaced when the query matches
    readonly property var actions: [
        { name: "Settings", sub: "System preferences", ic: "preferences-system", run: function () { Quickshell.execDetached(["qs", "ipc", "call", "settings", "toggle"]) } }
    ]
    function matchActions(q) {
        if (q === "") return []
        var out = []
        for (var i = 0; i < root.actions.length; i++) if (root.actions[i].name.toLowerCase().indexOf(q.toLowerCase()) >= 0) out.push(root.actions[i])
        return out
    }

    function mergeResults() {
        var out = []
        var a = root.appResults
        var hasQuery = root.query.trim().length > 0
        var acts = root.matchActions(root.query.trim())
        for (var ai = 0; ai < acts.length; ai++) out.push({ type: "action", name: acts[ai].name, sub: acts[ai].sub, iconSource: Quickshell.iconPath(acts[ai].ic, "preferences-system"), run: acts[ai].run })
        var capA = hasQuery ? Math.min(a.length, 6) : a.length   // leave room for files
        for (var i = 0; i < capA; i++) {
            var e = a[i]
            out.push({ type: "app", entry: e, name: e.name || "",
                       sub: e.genericName || e.comment || "",
                       iconSource: Quickshell.iconPath(e.icon, "application-x-executable") })
        }
        var f = root.fileResults
        for (var j = 0; j < f.length; j++) out.push(f[j])
        return out
    }

    function runFileSearch() {
        var q = root.query.trim()
        if (q.length < 2) { root.fileResults = []; return }
        root.fileQuery = q
        fileProc.running = false
        fileProc.command = ["sh", "-c", root.fileScript, "sh", q]
        fileProc.running = true
    }

    function launch(item, fresh) {
        if (!item) return
        // focus-or-launch: jump to the app's existing window unless a new
        // instance was explicitly asked for (middle click / fresh=true)
        if (item.type === "app") { if (item.entry && (fresh || !Globals.activateAppWindow(item.entry))) item.entry.execute() }
        else if (item.type === "action") { if (item.run) item.run() }
        else Quickshell.execDetached(["xdg-open", item.path])
        root.hide()
    }

    // ── the overlay window ────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.opened || root.held
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:applauncher"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: if (visible) input.forceActiveFocus()

        // click anywhere outside the panel → dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        // ── centered panel (sits in the upper third) ──
        Item {
            id: panelWrap
            width: 640
            height: panel.height
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.20

            opacity: root.opened ? 1 : 0
            scale: root.opened ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on scale   { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }


            Rectangle {
                id: panel
                width: parent.width
                height: content.implicitHeight
                radius: Theme.radius
                color: Theme.panel
                border.color: Theme.stroke
                border.width: 1
                layer.enabled: true
                layer.effect: Elevation {}
                Sheen { radius: parent.radius }

                // swallow clicks inside the panel so they don't dismiss it
                MouseArea { anchors.fill: parent }

                Column {
                    id: content
                    width: parent.width

                    // ── search row ──
                    Item {
                        width: parent.width
                        height: 58
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 14
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icSearch
                                font.family: Theme.fontIcons
                                font.pixelSize: 18
                                color: Theme.fgDim
                            }
                            TextInput {
                                id: input
                                width: parent.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.fg
                                font.family: Theme.fontDisplay
                                font.pixelSize: Theme.fsTitle
                                selectionColor: Theme.accent
                                selectByMouse: true
                                clip: true
                                onTextChanged: { root.query = text; root.selected = 0 }
                                Text {
                                    visible: input.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Search apps, files & folders…"
                                    color: Theme.fgDim
                                    font: input.font
                                }
                                Keys.onPressed: function (ev) {
                                    if (ev.key === Qt.Key_Escape) { root.hide(); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Up)   { root.selected = Math.max(root.selected - 1, 0); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.launch(root.results[root.selected]); ev.accepted = true }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Theme.stroke
                        visible: root.results.length > 0
                    }

                    // ── results ──
                    ListView {
                        id: list
                        width: parent.width
                        height: Math.min(root.results.length, 8) * 54
                        clip: true
                        model: root.results
                        currentIndex: root.selected
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: row
                            width: list.width
                            height: 54
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.selected

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 6
                                radius: Theme.radiusInner
                                color: row.sel ? Theme.accent : "transparent"
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 14
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 34
                                    sourceSize.width: 68; sourceSize.height: 68; mipmap: true
                                    source: row.modelData.iconSource || Quickshell.iconPath("application-x-executable")
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    Text {
                                        text: row.modelData.name || ""
                                        color: row.sel ? Theme.accentText : Theme.fg
                                        font.family: Theme.fontText
                                        font.pixelSize: Theme.fsBody
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: row.modelData.sub || ""
                                        visible: text.length > 0
                                        color: row.sel ? Theme.accentText : Theme.fgDim
                                        font.family: Theme.fontText
                                        font.pixelSize: Theme.fsSmall
                                        elide: Text.ElideRight
                                        width: list.width - 120
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onPositionChanged: root.selected = row.index
                                onClicked: function (mouse) { root.launch(row.modelData, mouse.button === Qt.MiddleButton) }
                            }
                        }
                    }
                }
            }
        }
    }
}
