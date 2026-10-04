import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs

// ewe.places — a compact file manager that pops up above the dock's folder
// button, or under the bar's. You browse INTO folders (no external file
// manager), with the current path + a back arrow across the top; a file opens
// with its default app (xdg-open). Drag any entry OUT to drop it as a file
// into another app (Slack, upload fields, …) — text/uri-list, the shell's
// drag-out idiom. Drop a file/folder ONTO the panel to PIN it; pinned items
// sit in a "Pinned" strip with a ✕ to remove.
//
// Its own PanelWindow, not an AnchoredPopup: the window masks ONLY the box,
// so the surrounding area passes input through — that is what lets a drag
// land on the app behind, and why there is no click-outside close (Esc
// closes). The open state still reaches the dock through Shell.setActive, so
// the dock item lights like any AnchoredPopup's would.
//
// Pinned folders are the user's `[[apps.places]]` (ewe-conf writes
// ~/.config/quickshell/places.json): read here through a watched FileView,
// written through `ewe-conf set --no-hooks apps.places` — the same file and
// the same writer as before 0.25, so ewe-settings and sync keep working.
//
// Entry points: the dock item's action `ewe.places.toggle` (registered
// here, run by the dock or by Widget.qml with the button's anchor) and IPC —
//     qs ipc call ewe.places toggle|show|hide      qs ipc call places toggle|show|hide   (legacy)
Scope {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})

    property bool open: false
    property var anchor: null          // { screen, x, y, edge } from Shell.anchorFor(); null = focused screen, centred, bottom
    property var openScreen: null

    property string home: ""
    property string cwd: ""            // directory currently being browsed
    property var entries: []           // [{ name, path, isDir, size }] of cwd
    property int sel: -1               // keyboard selection into rowsFlat
    property var pinned: []            // the pinned paths (places.json)
    property var pinTypes: ({})        // pinned path -> isDir (for icon + click)

    function tilde(p) { return (root.home && String(p).indexOf(root.home) === 0) ? "~" + String(p).slice(root.home.length) : p }
    function baseName(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i >= 0 ? (s.slice(i + 1) || "/") : s }
    function parentOf(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i > 0 ? s.slice(0, i) : "/" }
    function uriToPath(u) { var s = String(u).trim(); if (s.indexOf("file://") === 0) s = s.slice(7); try { s = decodeURIComponent(s) } catch (e) {} return s.replace(/\/+$/, "") }
    function fileUri(p) { return "file://" + p + "\r\n" }
    // Sizes the way the Writing guide wants them: decimal units, one decimal
    // below 10, a space before the unit. Folders show nothing.
    function humanSize(bytes) {
        var b = Number(bytes)
        if (!isFinite(b) || b < 0) return ""
        var units = ["B", "KB", "MB", "GB", "TB"], i = 0
        while (b >= 1000 && i < units.length - 1) { b /= 1000; i++ }
        var n = (i === 0) ? String(Math.round(b))
              : (b < 10) ? b.toFixed(1) : String(Math.round(b))
        return n + " " + units[i]
    }

    // ── open / close ──
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    function openAt(a) {
        if (a) root.anchor = a
        root.openScreen = (root.anchor && root.anchor.screen) ? root.anchor.screen : root.focusedScreen()
        Shell.closePopups("ewe.places")    // one add-on popup at a time
        root.open = true
    }
    function toggleAt(a) { if (root.open) root.close(); else root.openAt(a) }
    function close() { root.open = false }
    onOpenChanged: Shell.setActive("ewe.places.toggle", root.open)
    // another add-on's popup is opening (Shell.closePopups): this is not an
    // AnchoredPopup, so it joins the one-popup rule by hand
    Connections {
        target: Shell
        function onPopupsClosing(exceptId) { if (root.open && exceptId !== "ewe.places") root.close() }
    }

    // The dock item (manifest dockItem, drawn by the dock add-on) is hidden
    // when the `button` setting says bar-only; the dock filters on it live.
    readonly property string mode: (root.settings && root.settings.button) ? String(root.settings.button) : "auto"
    readonly property bool dockItemWanted: root.mode !== "bar"
    onDockItemWantedChanged: Shell.setDockItemShown("ewe.places", root.dockItemWanted)

    Component.onCompleted: {
        Shell.registerAction("ewe.places.toggle", function (a) { root.toggleAt(a) })
        Shell.setDockItemShown("ewe.places", root.dockItemWanted)
        root.openScreen = root.focusedScreen()
        initProc.running = true
    }
    Component.onDestruction: { Shell.registerAction("ewe.places.toggle", null); Shell.setDockItemShown("ewe.places", true) }

    IpcHandler {
        target: "ewe.places"
        function toggle(): void { root.toggleAt(null) }
        function show(): void { root.openAt(null) }
        function hide(): void { root.close() }
    }
    // the shell's target before 0.25 (manifest ipcAliases): old keybinds and
    // scripts keep working
    IpcHandler {
        target: "places"
        function toggle(): void { root.toggleAt(null) }
        function show(): void { root.openAt(null) }
        function hide(): void { root.close() }
    }

    // ── keyboard navigation: one flat list of the rows on screen — the
    //    pinned strip, then the folder — so Up/Down walk both, Enter opens
    //    the selection and Backspace goes back. ──
    readonly property var rowsFlat: {
        var out = [], p = root.pinned || []
        for (var i = 0; i < p.length; i++)
            out.push({ name: root.baseName(p[i]), path: p[i], isDir: root.pinTypes[p[i]] === true, pinned: true, size: -1 })
        for (var j = 0; j < root.entries.length; j++) {
            var e = root.entries[j]
            out.push({ name: e.name, path: e.path, isDir: e.isDir, pinned: false, size: e.size })
        }
        return out
    }
    function moveSel(d) {
        var n = root.rowsFlat.length
        if (n === 0) { root.sel = -1; return }
        root.sel = Math.max(0, Math.min(n - 1, (root.sel < 0 ? (d > 0 ? -1 : n) : root.sel) + d))
    }
    function activateSel() {
        var r = root.rowsFlat[root.sel]
        if (r) root.activate(r.path, r.isDir)
    }

    function enter(path) { root.cwd = path; root.sel = -1 }  // changing cwd re-lists
    function openFile(path) { Quickshell.execDetached(["xdg-open", path]) }
    function activate(path, isDir) { if (isDir) root.enter(path); else root.openFile(path) }
    function pinDrop(uris) {
        for (var i = 0; i < uris.length; i++) { var p = root.uriToPath(uris[i]); if (p && p.indexOf("/") === 0 && !root.isPinned(p)) root.togglePin(p) }
    }

    // ── pinned places: places.json in, ewe-conf out ──
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    function isPinned(p) { return (root.pinned || []).indexOf(p) >= 0 }
    function applyPinned(text) {
        try { var j = JSON.parse(text); root.pinned = Array.isArray(j) ? j : [] } catch (e) { root.pinned = [] }
        root.refreshPinTypes()
    }
    FileView {
        id: placesFile
        path: root.configHome + "/quickshell/places.json"
        watchChanges: true
        printErrors: false
        onFileChanged: placesFile.reload()
        onLoaded: root.applyPinned(placesFile.text())
        onLoadFailed: root.applyPinned("[]")      // no file yet: nothing pinned
    }
    // ewe-conf is the only writer of ewe.conf (Rule 1): `apps.places` is the
    // list, and ewe-conf mirrors it into places.json, which the FileView
    // above then re-reads. Found the way the shell finds it — beside the
    // payload the running quickshell dir links into — with the plugin tool's
    // sibling (the nested harness) and PATH as fallbacks. --no-hooks: the
    // shell itself is what a hook would poke.
    Process {
        id: pinWriter
        stdout: StdioCollector {}
        stderr: StdioCollector { onStreamFinished: if (this.text.trim()) Log.warn("ewe.places", "ewe-conf:", this.text.trim()) }
    }
    function togglePin(p) {
        if (!p) return
        var a = (root.pinned || []).slice()
        var i = a.indexOf(p)
        if (i >= 0) a.splice(i, 1); else a.push(p)
        root.pinned = a                            // optimistic; the file watch confirms
        pinWriter.command = ["sh", "-c",
            't="$HOME/.config/quickshell/../../bin/ewe-conf"; ' +
            '[ -x "$t" ] || t="${EWE_PLUGIN_TOOL%/*}/ewe-conf"; ' +
            '[ -x "$t" ] || t="$(command -v ewe-conf)"; ' +
            '[ -n "$t" ] || { echo "ewe-conf not found" >&2; exit 1; }; ' +
            'exec "$t" set --no-hooks apps.places "$1"', "sh", JSON.stringify(a)]
        pinWriter.running = false; pinWriter.running = true
    }

    // ── directory lister: folders + files (no dotfiles), type-tagged ──
    readonly property string listScript: 'D="$1"; [ -d "$D" ] || exit 0; find "$D" -maxdepth 1 -mindepth 1 -not -name ".*" -printf "%Y\\t%s\\t%f\\n" 2>/dev/null'
    Process {
        id: lister
        running: false
        command: ["sh", "-c", root.listScript, "sh", root.cwd]
        stdout: StdioCollector { onStreamFinished: {
            var dirs = [], files = [], ls = this.text.split("\n")
            for (var i = 0; i < ls.length; i++) {
                var parts = ls[i].split("\t"); if (parts.length < 3) continue
                var ty = parts[0], sz = parts[1], nm = parts.slice(2).join("\t")
                if (!nm) continue
                var e = { name: nm, path: (root.cwd === "/" ? "" : root.cwd) + "/" + nm,
                          isDir: (ty === "d"), size: Number(sz) }
                ;(e.isDir ? dirs : files).push(e)
            }
            var byName = function (a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) }
            dirs.sort(byName); files.sort(byName)
            root.entries = dirs.concat(files)
        } }
    }
    function relist() { if (!root.cwd) return; lister.command = ["sh", "-c", root.listScript, "sh", root.cwd]; lister.running = false; lister.running = true }
    onCwdChanged: root.relist()

    Process {
        id: initProc; running: false
        command: ["sh", "-c", "echo $HOME"]
        stdout: StdioCollector { onStreamFinished: { root.home = this.text.trim(); if (!root.cwd) root.cwd = root.home } }
    }

    // resolve dir/file type for the pinned paths (icon + click behaviour)
    Process { id: pinTyper; running: false
        stdout: StdioCollector { onStreamFinished: {
            var m = {}, ls = this.text.split("\n")
            for (var i = 0; i < ls.length; i++) { var t = ls[i].indexOf("\t"); if (t < 0) continue; m[ls[i].slice(t + 1)] = (ls[i].slice(0, t) === "d") }
            root.pinTypes = m
        } }
    }
    function refreshPinTypes() {
        var p = root.pinned || []
        if (!p.length) { root.pinTypes = ({}); return }
        // printf, not echo: bash's echo doesn't expand \t, so a tab-splitting
        // parser never matched — every pin looked like a file
        pinTyper.command = ["sh", "-c", 'for p in "$@"; do if [ -d "$p" ]; then printf "d\\t%s\\n" "$p"; else printf "f\\t%s\\n" "$p"; fi; done', "sh"].concat(p)
        pinTyper.running = false; pinTyper.running = true
    }

    PanelWindow {
        id: win
        visible: root.open || win.held
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:places"      // as before (hyprland.lua rules, Glass blur)
        anchors { top: true; bottom: true; left: true; right: true }

        // Mask ONLY the box: input outside it passes through to the app below, so
        // a folder/file drag can land on Slack/etc. (see header). No outside-click close.
        mask: Region { item: box }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections { target: root; function onOpenChanged() {
            if (root.open) { closeTimer.stop(); win.held = true; if (root.home && !root.cwd) root.cwd = root.home; root.relist(); placesFile.reload(); box.forceActiveFocus() }
            else closeTimer.restart()
        } }

        Rectangle {
            id: box
            focus: true
            readonly property int edgeGap: Theme.spaceS + Theme.spaceXs
            // bottom: the dock's strip (Shell.bottomInset — no gap when no
            // dock is there) plus the card's own gap above it; top: the bar
            // (the window spans the full output) plus spaceXs under it
            readonly property bool fromTop: root.anchor !== null && root.anchor.edge === "top"
            readonly property int dockGap: Shell.bottomInset + edgeGap
            readonly property int topGap: Theme.barHeight + Theme.spaceXs
            readonly property real ax: root.anchor ? root.anchor.x : parent.width / 2
            x: Math.round(Math.max(edgeGap, Math.min(parent.width - width - edgeGap, ax - width / 2)))
            width: Theme.panelMd
            // at most panelMd + controlXl + spaceMd + spaceXs (a dozen rows)
            // tall — what it has always been — and never past the screen
            height: Math.min(Theme.panelMd + Theme.controlXl + Theme.spaceMd + Theme.spaceXs,
                             parent.height - (fromTop ? topGap : dockGap) - 2 * edgeGap)
            y: fromTop ? topGap : Math.max(edgeGap, parent.height - height - dockGap)
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            // an accent outline while something is being dropped on the panel
            border.color: dropArea.containsDrag ? Theme.accent : Theme.borderSubtle
            border.width: Theme.borderWidth1
            // a dock panel opens and closes with a plain fade — no slide
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            layer.enabled: true
            layer.effect: Elevation {}

            // ── keyboard navigation ──
            Keys.onEscapePressed: root.close()
            Keys.onUpPressed: root.moveSel(-1)
            Keys.onDownPressed: root.moveSel(1)
            Keys.onReturnPressed: root.activateSel()
            Keys.onEnterPressed: root.activateSel()
            Keys.onPressed: function (ev) {
                if (ev.key === Qt.Key_Backspace) {
                    if (root.cwd !== "/" && root.cwd !== "") root.enter(root.parentOf(root.cwd))
                    ev.accepted = true
                }
            }

            // drop a file/folder onto the panel → pin it
            DropArea {
                id: dropArea
                anchors.fill: parent
                onEntered: function (d) { d.accept(Qt.CopyAction) }
                onDropped: function (d) {
                    var uris = d.hasUrls ? d.urls : (d.getDataAsString ? d.getDataAsString("text/uri-list").split(/\r?\n/) : [])
                    root.pinDrop(uris)
                }
            }

            // ── a md ghost Icon button (back / home / pin) ──
            component IconBtn: Rectangle {
                property string glyph: ""
                property bool enabledState: true
                property bool selected: false      // a selected ghost button: accentSubtle, accentText glyph
                signal act()
                width: Theme.controlMd; height: Theme.controlMd
                radius: Theme.radiusPrimary
                color: !enabledState ? "transparent"
                     : selected ? Theme.accentSubtle
                     : ibMa.pressed ? Theme.surfacePressed
                     : ibMa.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Text {
                    anchors.centerIn: parent; text: parent.glyph
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                    color: !parent.enabledState ? Theme.textDisabled
                         : parent.selected ? Theme.accentText : Theme.textPrimary
                }
                MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; enabled: parent.enabledState; cursorShape: Qt.PointingHandCursor; onClicked: parent.act() }
            }

            // ── one filesystem row (browse entry OR pinned item) ──
            // controlLg tall, radiusPrimary, an iconLg glyph (folders in
            // accentText), the name at body size, a file's size as a caption,
            // and a chevron on folders (Places card #4).
            component FsRow: Rectangle {
                id: fr
                property string rName: ""
                property string rPath: ""
                property bool rIsDir: false
                property bool rPinned: false
                property real rSize: -1
                property bool rSelected: false
                width: parent ? parent.width : Theme.panelMd
                height: Theme.controlLg; radius: Theme.radiusPrimary
                color: frMa.drag.active ? Theme.surfaceOverlay
                     : frMa.containsMouse ? Theme.surfaceHover : "transparent"
                // the focus ring rides the row's own edge, inside it
                border.color: fr.rSelected ? Theme.focusRing : "transparent"
                border.width: fr.rSelected ? Theme.focusWidth : 0
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                layer.enabled: frMa.drag.active
                layer.effect: Elevation {}

                Row {
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                    anchors.right: rightBtns.left; anchors.rightMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceS
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: fr.rIsDir ? Theme.icFolder : Theme.icFile
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                        color: fr.rIsDir ? Theme.accentText : Theme.textSecondary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: fr.rName; color: Theme.textPrimary
                        font.family: Theme.type.body.family
                        font.pixelSize: Theme.type.body.size
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, fr.width - 5 * Theme.spaceMd)
                    }
                }

                // drag OUT → file URI (drop into another app)
                Item {
                    id: dragProxy; width: 1; height: 1
                    Drag.active: frMa.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.proposedAction: Qt.CopyAction
                    Drag.mimeData: ({ "text/uri-list": root.fileUri(fr.rPath) })
                }
                MouseArea {
                    id: frMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    drag.target: dragProxy
                    onClicked: root.activate(fr.rPath, fr.rIsDir)
                }

                Row {
                    id: rightBtns
                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXs
                    // a file's size
                    Text {
                        visible: !fr.rIsDir && fr.rSize >= 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.humanSize(fr.rSize)
                        color: Theme.textMuted
                        font.family: Theme.type.caption.family
                        font.pixelSize: Theme.type.caption.size
                        font.features: ({ "tnum": 1 })
                    }
                    // folder hint chevron (browse entries)
                    Text { visible: fr.rIsDir && !fr.rPinned; anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronRight; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textMuted }
                    // unpin ✕ (pinned items)
                    Rectangle {
                        visible: fr.rPinned
                        width: Theme.controlSm; height: Theme.controlSm
                        radius: Theme.radiusSecondary
                        anchors.verticalCenter: parent.verticalCenter
                        color: upMa.containsMouse ? Theme.dangerSubtle : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: upMa.containsMouse ? Theme.danger : Theme.textSecondary }
                        MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePin(fr.rPath) }
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceS + Theme.spaceXs
                spacing: Theme.spaceS

                // ── address row: back · home · path · pin-current ──
                Row {
                    id: addressRow
                    width: parent.width; height: Theme.controlMd; spacing: Theme.spaceXs
                    IconBtn { glyph: Theme.icBack; enabledState: root.cwd !== "/" && root.cwd !== ""; anchors.verticalCenter: parent.verticalCenter; onAct: root.enter(root.parentOf(root.cwd)) }
                    IconBtn { glyph: Theme.icHome; anchors.verticalCenter: parent.verticalCenter; onAct: root.enter(root.home) }
                    // the path in a small field: the Text field box (sunken,
                    // borderStrong), the mono style (Places card #2)
                    Rectangle {
                        width: parent.width - 3 * Theme.controlMd - 3 * Theme.spaceXs
                        height: Theme.controlMd; radius: Theme.radiusPrimary
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.surfaceSunken
                        border.color: Theme.borderStrong; border.width: Theme.fieldBorderWidth
                        Text {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tilde(root.cwd); color: Theme.textPrimary
                            font.family: Theme.type.mono.family
                            font.pixelSize: Theme.type.mono.size
                            elide: Text.ElideLeft
                        }
                    }
                    IconBtn { glyph: (root.isPinned(root.cwd) ? Theme.icStar : Theme.icPin); selected: root.isPinned(root.cwd); enabledState: root.cwd !== ""; anchors.verticalCenter: parent.verticalCenter; onAct: root.togglePin(root.cwd) }
                }

                Flickable {
                    id: list
                    width: parent.width; height: parent.height - y
                    contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    // keep the keyboard selection on screen
                    function reveal(row) {
                        var y = row.mapToItem(col, 0, 0).y
                        if (y < contentY) contentY = y
                        else if (y + row.height > contentY + height) contentY = y + row.height - height
                    }
                    Column {
                        id: col
                        width: parent.width; spacing: Theme.spaceXxs

                        // pinned strip
                        SectionTitle { width: parent.width; first: true; visible: (root.pinned || []).length > 0; text: "Pinned" }
                        Repeater {
                            model: (root.pinned || [])
                            delegate: FsRow {
                                id: pinRow
                                required property var modelData
                                required property int index
                                width: col.width
                                onRSelectedChanged: if (rSelected) list.reveal(pinRow)
                                rName: root.baseName(modelData); rPath: modelData
                                rIsDir: root.pinTypes[modelData] === true; rPinned: true
                                rSelected: root.sel === index
                            }
                        }
                        Rectangle { visible: (root.pinned || []).length > 0; width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }

                        // current directory
                        SectionTitle { width: parent.width; visible: root.entries.length > 0; text: "Folder" }
                        Repeater {
                            model: root.entries
                            delegate: FsRow {
                                id: entRow
                                required property var modelData
                                required property int index
                                width: col.width
                                onRSelectedChanged: if (rSelected) list.reveal(entRow)
                                rName: modelData.name; rPath: modelData.path
                                rIsDir: modelData.isDir; rSize: modelData.isDir ? -1 : modelData.size
                                rSelected: root.sel === (root.pinned || []).length + index
                            }
                        }
                        Text {
                            width: parent.width; visible: root.entries.length === 0
                            text: "This folder is empty"
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.textMuted
                            font.family: Theme.type.label.family
                            font.pixelSize: Theme.type.label.size
                            topPadding: Theme.spaceMd
                        }
                    }
                }
            }
        }
    }
}
