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
    property var entries: []           // [{ name, path, isDir }] of cwd
    property var pinTypes: ({})        // pinned path -> isDir (for icon + click)

    function tilde(p) { return (root.home && String(p).indexOf(root.home) === 0) ? "~" + String(p).slice(root.home.length) : p }
    function baseName(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i >= 0 ? (s.slice(i + 1) || "/") : s }
    function parentOf(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i > 0 ? s.slice(0, i) : "/" }
    function uriToPath(u) { var s = String(u).trim(); if (s.indexOf("file://") === 0) s = s.slice(7); try { s = decodeURIComponent(s) } catch (e) {} return s.replace(/\/+$/, "") }
    function fileUri(p) { return "file://" + p + "\r\n" }

    function enter(path) { root.cwd = path }                 // changing cwd re-lists
    function openFile(path) { Quickshell.execDetached(["xdg-open", path]) }
    function activate(path, isDir) { if (isDir) root.enter(path); else root.openFile(path) }
    function pinDrop(uris) {
        for (var i = 0; i < uris.length; i++) { var p = root.uriToPath(uris[i]); if (p && p.indexOf("/") === 0 && !Globals.isPinnedPlace(p)) Globals.togglePinPlace(p) }
    }

    // ── directory lister: folders + files (no dotfiles), type-tagged ──
    Process {
        id: lister
        running: false
        command: ["sh", "-c", 'D="$1"; [ -d "$D" ] || exit 0; find "$D" -maxdepth 1 -mindepth 1 -not -name ".*" -printf "%Y\\t%f\\n" 2>/dev/null', "sh", root.cwd]
        stdout: StdioCollector { onStreamFinished: {
            var dirs = [], files = [], ls = this.text.split("\n")
            for (var i = 0; i < ls.length; i++) {
                var t = ls[i].indexOf("\t"); if (t < 0) continue
                var ty = ls[i].slice(0, t), nm = ls[i].slice(t + 1)
                if (!nm) continue
                var e = { name: nm, path: (root.cwd === "/" ? "" : root.cwd) + "/" + nm, isDir: (ty === "d") }
                ;(e.isDir ? dirs : files).push(e)
            }
            var byName = function (a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) }
            dirs.sort(byName); files.sort(byName)
            root.entries = dirs.concat(files)
        } }
    }
    onCwdChanged: if (root.cwd) { lister.command = ["sh", "-c", 'D="$1"; [ -d "$D" ] || exit 0; find "$D" -maxdepth 1 -mindepth 1 -not -name ".*" -printf "%Y\\t%f\\n" 2>/dev/null', "sh", root.cwd]; lister.running = false; lister.running = true }

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
            x: Math.max(12, Math.min(parent.width - width - 12, Globals.placesAnchorX - width / 2))
            y: parent.height - height - 90
            width: 400; height: 470
            radius: Theme.radius; color: Theme.bg1
            border.color: Theme.stroke2; border.width: Theme.borderThin
            Sheen { radius: parent.radius }
            opacity: Globals.placesOpen ? 1 : 0
            scale: Globals.placesOpen ? 1 : 0.96
            transformOrigin: Item.BottomLeft
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            layer.enabled: true
            layer.effect: Elevation {}

            Keys.onEscapePressed: Globals.placesOpen = false

            // drop a file/folder onto the panel → pin it
            DropArea {
                anchors.fill: parent
                onEntered: function (d) { d.accept(Qt.CopyAction) }
                onDropped: function (d) {
                    var uris = d.hasUrls ? d.urls : (d.getDataAsString ? d.getDataAsString("text/uri-list").split(/\r?\n/) : [])
                    root.pinDrop(uris)
                }
            }

            // ── a small round icon button (back / home / pin) ──
            component IconBtn: Rectangle {
                property string glyph: ""
                property bool enabledState: true
                signal act()
                width: 28; height: 28; radius: Theme.r(8)
                color: ibMa.containsMouse && enabledState ? Theme.subtleHover : Theme.subtle
                opacity: enabledState ? 1 : 0.35
                Text { anchors.centerIn: parent; text: parent.glyph; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.fg1 }
                MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; enabled: parent.enabledState; cursorShape: Qt.PointingHandCursor; onClicked: parent.act() }
            }

            // ── one filesystem row (browse entry OR pinned item) ──
            component FsRow: Rectangle {
                id: fr
                property string rName: ""
                property string rPath: ""
                property bool rIsDir: false
                property bool rPinned: false
                width: parent ? parent.width : 100
                height: 34; radius: Theme.r(8)
                color: frMa.containsMouse ? Theme.subtleHover : Theme.subtle

                Row {
                    anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: rightBtns.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter; spacing: 9
                    Image {
                        anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; sourceSize.width: 44; sourceSize.height: 44; mipmap: true
                        source: Quickshell.iconPath(fr.rIsDir ? "folder" : "text-x-generic", fr.rIsDir ? "folder" : "application-x-zerosize")
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: fr.rName; color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; elide: Text.ElideRight; width: Math.min(implicitWidth, fr.width - 90) }
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
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    // folder hint chevron (browse entries)
                    Text { visible: fr.rIsDir && !fr.rPinned; anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronRight; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fg3 }
                    // unpin ✕ (pinned items)
                    Rectangle { visible: fr.rPinned; width: 20; height: 20; radius: 10; anchors.verticalCenter: parent.verticalCenter
                        color: upMa.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.35)
                        Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fg1 }
                        MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.togglePinPlace(fr.rPath) }
                    }
                }
            }

            Column {
                anchors.fill: parent; anchors.margins: 12; spacing: 8

                // ── address bar: back · home · path · pin-current ──
                Row {
                    width: parent.width; height: 30; spacing: 4
                    IconBtn { glyph: Theme.icBack; enabledState: root.cwd !== "/" && root.cwd !== ""; anchors.verticalCenter: parent.verticalCenter; onAct: root.enter(root.parentOf(root.cwd)) }
                    IconBtn { glyph: Theme.icHome; anchors.verticalCenter: parent.verticalCenter; onAct: root.enter(root.home) }
                    Rectangle {
                        width: parent.width - 28*3 - 4*3; height: 30; radius: Theme.radiusInner
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.bg3; border.color: Theme.stroke2; border.width: Theme.borderThin
                        Text { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            text: root.tilde(root.cwd); color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideLeft }
                    }
                    IconBtn { glyph: (Globals.isPinnedPlace(root.cwd) ? Theme.icStar : Theme.icPin); enabledState: root.cwd !== ""; anchors.verticalCenter: parent.verticalCenter; onAct: Globals.togglePinPlace(root.cwd) }
                }

                Flickable {
                    width: parent.width; height: parent.height - y
                    contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: col
                        width: parent.width; spacing: 2

                        // pinned strip
                        Text { width: parent.width; visible: (Globals.pinnedPlaces || []).length > 0; text: "PINNED"; color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold; bottomPadding: 2 }
                        Repeater {
                            model: (Globals.pinnedPlaces || [])
                            delegate: FsRow { required property var modelData; width: col.width; rName: root.baseName(modelData); rPath: modelData; rIsDir: root.pinTypes[modelData] === true; rPinned: true }
                        }
                        Rectangle { visible: (Globals.pinnedPlaces || []).length > 0; width: parent.width; height: 1; color: Theme.stroke3 }

                        // current directory
                        Text { width: parent.width; visible: root.entries.length > 0; text: "FOLDER"; color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold; topPadding: 4; bottomPadding: 2 }
                        Repeater {
                            model: root.entries
                            delegate: FsRow { required property var modelData; width: col.width; rName: modelData.name; rPath: modelData.path; rIsDir: modelData.isDir }
                        }
                        Text { width: parent.width; visible: root.entries.length === 0; text: "Empty folder"; color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; topPadding: 10 }
                    }
                }
            }
        }
    }
}
