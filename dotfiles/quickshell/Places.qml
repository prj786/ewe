import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// Places — a compact file manager that pops up above the dock's folder button.
// You browse INTO folders (no external Dolphin), with the current path + a back
// arrow across the top. Drag any entry OUT to drop it as a file into another app
// (Slack, upload fields, …) — text/uri-list, same idiom as ScreenshotPreview.
// Drop a file/folder ONTO the panel to PIN it; pinned items sit in a "Pinned"
// strip with a ✕ to remove. The window masks ONLY the box, so the surrounding
// area passes input through — that's what lets a drag land on the app behind.
// Themed from Theme.qml.
Scope {
    id: root
    function g(c) { return String.fromCodePoint(c) }

    property string home: ""
    property string cwd: ""            // directory currently being browsed
    property var entries: []           // [{ name, path, isDir, size }] of cwd
    property int sel: -1               // keyboard selection into rowsFlat
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

    // ── keyboard navigation (new, per the card): one flat list of the rows
    //    on screen — the pinned strip, then the folder — so Up/Down walk
    //    both, Enter opens the selection and Backspace goes back. ──
    readonly property var rowsFlat: {
        var out = [], p = Globals.pinnedPlaces || []
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
        for (var i = 0; i < uris.length; i++) { var p = root.uriToPath(uris[i]); if (p && p.indexOf("/") === 0 && !Globals.isPinnedPlace(p)) Globals.togglePinPlace(p) }
    }

    // ── directory lister: folders + files (no dotfiles), type-tagged ──
    Process {
        id: lister
        running: false
        command: ["sh", "-c", 'D="$1"; [ -d "$D" ] || exit 0; find "$D" -maxdepth 1 -mindepth 1 -not -name ".*" -printf "%Y\\t%s\\t%f\\n" 2>/dev/null', "sh", root.cwd]
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
    onCwdChanged: if (root.cwd) { lister.command = ["sh", "-c", 'D="$1"; [ -d "$D" ] || exit 0; find "$D" -maxdepth 1 -mindepth 1 -not -name ".*" -printf "%Y\\t%s\\t%f\\n" 2>/dev/null', "sh", root.cwd]; lister.running = false; lister.running = true }

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
        var p = Globals.pinnedPlaces || []
        if (!p.length) { root.pinTypes = ({}); return }
        // printf, not echo: bash's echo doesn't expand \t, so the parser above
        // (which splits on a real tab) never matched — every pin looked like a
        // file, which is why pinned FOLDERS showed the file icon.
        pinTyper.command = ["sh", "-c", 'for p in "$@"; do if [ -d "$p" ]; then printf "d\\t%s\\n" "$p"; else printf "f\\t%s\\n" "$p"; fi; done', "sh"].concat(p)
        pinTyper.running = false; pinTyper.running = true
    }
    Connections { target: Globals; function onPinnedPlacesChanged() { root.refreshPinTypes() } }

    Component.onCompleted: { root.openScreen = root.focusedScreen(); initProc.running = true; root.refreshPinTypes() }

    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }

    IpcHandler {
        target: "places"
        function toggle(): void { Globals.launcherOpen = false; Globals.storeOpen = false; Globals.placesOpen = !Globals.placesOpen }
        function show(): void { Globals.placesOpen = true }
        function hide(): void { Globals.placesOpen = false }
    }

    PanelWindow {
        id: win
        visible: Globals.placesOpen || win.held
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:places"
        anchors { top: true; bottom: true; left: true; right: true }

        // Mask ONLY the box: input outside it passes through to the app below, so
        // a folder/file drag can land on Slack/etc. (see header). No outside-click close.
        mask: Region { item: box }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections { target: Globals; function onPlacesOpenChanged() {
            if (Globals.placesOpen) { closeTimer.stop(); win.held = true; root.openScreen = root.focusedScreen(); if (root.home && !root.cwd) root.cwd = root.home; lister.running = true; root.refreshPinTypes(); box.forceActiveFocus() }
            else closeTimer.restart()
        } }

        Rectangle {
            id: box
            focus: true
            readonly property int edgeGap: Theme.spaceS + Theme.spaceXs
            // the dock's own strip (items + spaceS padding, windowGap above
            // the edge) plus the card's spaceS + spaceXs gap above it
            readonly property int dockGap: Theme.dockClearance + edgeGap
            x: Math.max(edgeGap, Math.min(parent.width - width - edgeGap, Globals.placesAnchorX - width / 2))
            width: Theme.panelMd
            // at most panelMd + controlXl + spaceMd + spaceXs (a dozen rows)
            // tall — what it has always been — and never past the screen
            height: Math.min(Theme.panelMd + Theme.controlXl + Theme.spaceMd + Theme.spaceXs,
                             parent.height - dockGap - 2 * edgeGap)
            // a fade plus a short rise from its own edge; Reduce motion zeroes
            // the offset through Theme.slideOffset, leaving the fade
            y: Math.max(edgeGap, parent.height - height - dockGap)
               + (Globals.placesOpen ? 0 : Theme.slideOffset)
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            // an accent outline while something is being dropped on the panel
            border.color: dropArea.containsDrag ? Theme.accent : Theme.borderSubtle
            border.width: Theme.borderWidth1
            opacity: Globals.placesOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            layer.enabled: true
            layer.effect: Elevation {}

            // ── keyboard navigation (new, per the card) ──
            Keys.onEscapePressed: Globals.placesOpen = false
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
                    // a file's size (new, per the card)
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
                        MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.togglePinPlace(fr.rPath) }
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
                    // borderStrong), Geist Mono 12px (Places card #2)
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
                    IconBtn { glyph: (Globals.isPinnedPlace(root.cwd) ? Theme.icStar : Theme.icPin); selected: Globals.isPinnedPlace(root.cwd); enabledState: root.cwd !== ""; anchors.verticalCenter: parent.verticalCenter; onAct: Globals.togglePinPlace(root.cwd) }
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
                        SectionTitle { width: parent.width; first: true; visible: (Globals.pinnedPlaces || []).length > 0; text: "Pinned" }
                        Repeater {
                            model: (Globals.pinnedPlaces || [])
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
                        Rectangle { visible: (Globals.pinnedPlaces || []).length > 0; width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }

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
                                rSelected: root.sel === (Globals.pinnedPlaces || []).length + index
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
