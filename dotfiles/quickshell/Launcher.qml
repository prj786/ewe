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
    // Only what has no .desktop entry of its own. ewe-settings ships
    // ewe-settings.desktop, so listing Settings here too put TWO identical
    // results in the launcher that opened the same window. The synthetic one
    // survives solely for a machine where the app is absent and the in-shell
    // fallback panel is the only Settings there is.
    readonly property var actions: Globals.settingsAppInstalled ? [] : [
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
        if (item.type === "app") { Globals.launchEntry(item.entry, fresh) }
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

        // ── a keyboard key, for the search hint and the footer ──
        component Kbd: Rectangle {
            property string key: ""
            implicitWidth: Math.max(Theme.lineHeightS + 3 * Theme.borderWidth1,
                                    kt.implicitWidth + 2 * Theme.spaceXs)
            implicitHeight: kt.implicitHeight + 2 * Theme.borderWidth2
            radius: Theme.radiusSlight
            color: Theme.surfaceRaised
            border.color: Theme.borderStrong
            border.width: Theme.borderWidth1
            Text {
                id: kt
                anchors.centerIn: parent
                text: parent.key
                color: Theme.textSecondary
                font.family: Theme.type.mono.family
                font.pixelSize: Theme.type.caption.size
                font.weight: Theme.fontWeightMedium
            }
        }

        // ── centered panel (sits in the upper third) ──
        Item {
            id: panelWrap
            width: Theme.panelLg
            height: panel.height
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.20 + (root.opened ? 0 : Theme.slideOffset)

            opacity: root.opened ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }


            Rectangle {
                id: panel
                width: parent.width
                height: content.implicitHeight
                // the panel radius plus a step, so the rows inside stay
                // concentric with it (Launcher card #1)
                radius: Theme.r(Theme.radiusRounded + Theme.spaceXs)
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                clip: true
                layer.enabled: true
                layer.effect: Elevation {}

                // swallow clicks inside the panel so they don't dismiss it
                MouseArea { anchors.fill: parent }

                Column {
                    id: content
                    width: parent.width

                    // ── search row: the xl Search field, borderless inside
                    //    the panel, with Esc as its hint (Launcher card #2) ──
                    Item {
                        id: searchRow
                        width: parent.width
                        height: Theme.controlXl + 2 * Theme.spaceS
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceMd
                            anchors.rightMargin: Theme.spaceMd
                            spacing: Theme.spaceS
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icSearch
                                font.family: Theme.fontIcons
                                font.pixelSize: Theme.iconLg
                                color: Theme.textMuted
                            }
                            TextInput {
                                id: input
                                width: parent.width - Theme.iconLg - escHint.width - 2 * Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.textPrimary
                                font.family: Theme.type.bodyLg.family
                                font.pixelSize: Theme.type.bodyLg.size
                                selectionColor: Theme.accent
                                selectByMouse: true
                                clip: true
                                onTextChanged: { root.query = text; root.selected = 0 }
                                Text {
                                    visible: input.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Search apps, settings and files"
                                    color: Theme.textMuted
                                    font: input.font
                                }
                                Keys.onPressed: function (ev) {
                                    // Esc clears the query, a second Esc closes
                                    if (ev.key === Qt.Key_Escape) {
                                        if (input.text !== "") input.text = ""; else root.hide()
                                        ev.accepted = true
                                    }
                                    else if (ev.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Up)   { root.selected = Math.max(root.selected - 1, 0); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.launch(root.results[root.selected]); ev.accepted = true }
                                }
                            }
                            Kbd { id: escHint; anchors.verticalCenter: parent.verticalCenter; key: "Esc" }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: Theme.borderWidth1
                        color: Theme.borderSubtle
                        visible: root.results.length > 0
                    }

                    // ── results: control2xl rows with an icon2xl icon, the
                    //    title at body weight medium, the folder or generic
                    //    name as a caption, and the running key as the hint ──
                    ListView {
                        id: list
                        width: parent.width
                        // at most 8 rows, and never past the bottom of the
                        // screen — the footer's hints must stay visible
                        height: Math.min(Math.min(root.results.length, 8) * Theme.control2xl,
                                         Math.max(Theme.control2xl,
                                                  win.height - panelWrap.y - searchRow.height
                                                  - foot.height - Theme.spaceLg))
                        topMargin: root.results.length > 0 ? Theme.spaceXs : 0
                        bottomMargin: root.results.length > 0 ? Theme.spaceXs : 0
                        clip: true
                        model: root.results
                        currentIndex: root.selected
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: row
                            width: list.width
                            height: Theme.control2xl
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.selected

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spaceS
                                anchors.rightMargin: Theme.spaceS
                                radius: Theme.radiusPrimary
                                // selection is a surface step, never an accent
                                // fill: the row's own text has to stay readable
                                // (pointing at a row selects it, so hover and the
                                // keyboard selection are the same surfaceHover)
                                color: row.sel || rowMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spaceMd
                                anchors.rightMargin: Theme.spaceMd
                                spacing: Theme.spaceS + Theme.spaceXs
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.icon2xl; height: Theme.icon2xl
                                    sourceSize.width: 2 * Theme.icon2xl; sourceSize.height: 2 * Theme.icon2xl
                                    mipmap: true
                                    source: row.modelData.iconSource || Quickshell.iconPath("application-x-executable")
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: row.modelData.name || ""
                                        color: Theme.textPrimary
                                        font.family: Theme.type.bodyStrong.family
                                        font.pixelSize: Theme.type.bodyStrong.size
                                        font.weight: Theme.fontWeightMedium
                                    }
                                    Text {
                                        text: row.modelData.sub || ""
                                        visible: text.length > 0
                                        color: Theme.textMuted
                                        font.family: Theme.type.caption.family
                                        font.pixelSize: Theme.type.caption.size
                                        elide: Text.ElideRight
                                        width: list.width - Theme.icon2xl - 4 * Theme.spaceMd
                                    }
                                }
                            }
                            // the trailing hint: the key that runs the selection
                            Kbd {
                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceMd
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.sel
                                key: "Enter"
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onPositionChanged: root.selected = row.index
                                onClicked: function (mouse) { root.launch(row.modelData, mouse.button === Qt.MiddleButton) }
                            }
                        }
                    }

                    // ── footer: what the keyboard does, on surfaceBase ──
                    Rectangle {
                        id: foot
                        width: parent.width
                        height: hints.implicitHeight + 2 * Theme.spaceS
                        color: Theme.surfaceBase
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: Theme.borderWidth1; color: Theme.borderSubtle
                        }
                        Row {
                            id: hints
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            spacing: Theme.spaceMd
                            Row {
                                spacing: Theme.spaceXs
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "↑" }
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "↓" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Move"; color: Theme.textMuted
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                }
                            }
                            Row {
                                spacing: Theme.spaceXs
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "Enter" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Open"; color: Theme.textMuted
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                }
                            }
                            Row {
                                spacing: Theme.spaceXs
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "Esc" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Close"; color: Theme.textMuted
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
