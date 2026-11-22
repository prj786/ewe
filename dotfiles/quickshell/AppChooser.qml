import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// AppChooser — "Open with" for every app (RFC-011, design system: File
// picker, Open with). xdg-desktop-portal asks when an app opens a file or a
// link with "ask" set, or when nothing is set to open that type; ewe-portal
// writes the request and calls:
//
//     qs ipc call appchooser open <request.json>   → "ok"
//     qs ipc call appchooser update <request.json> the list of apps changed
//     qs ipc call appchooser close <id>            the app gave up
//     qs ipc call appchooser ping <id>             "open" · "idle" · "unknown"
//     qs ipc call appchooser select <desktop id>   a scripted answer (tests)
//     qs ipc call appchooser cancel
//
// The answer goes back as org.ewe.Portal1.Answer(id, {"ok", "choice"}).
//
//   card    Dialog md: panelMd (400) wide, surfaceRaised, a borderWidth1
//           borderSubtle outline, radiusRounded, shadowFloat, spaceMd padding
//           and between sections, centred on the focused screen over `scrim`
//   head    "Open with" in h3, the file's name in body textSecondary
//   list    control2xl rows with the app's iconXl icon and name; the last
//           choice first and selected (accentSubtle, a tick); at most 6 rows,
//           then it scrolls
//   empty   Empty state (compact): "No app opens this yet"
//   footer  above a borderWidth1 divider: "Find an app in Komble…" (ghost,
//           left), Cancel (ghost) and Open (primary) on the right
Scope {
    id: root

    property var req: null
    readonly property bool open: root.req !== null
    property int sel: 0
    property bool busy: false

    readonly property var apps: {
        var out = [], ids = root.req && root.req.choices ? root.req.choices.slice() : []
        var last = root.req ? root.req.last_choice : ""
        if (last && ids.indexOf(last) > 0) { ids.splice(ids.indexOf(last), 1); ids.unshift(last) }
        for (var i = 0; i < ids.length; i++) {
            var e = DesktopEntries.byId(ids[i]) || DesktopEntries.heuristicLookup(ids[i])
            out.push({ id: ids[i], name: e && e.name ? e.name : ids[i],
                       icon: e && e.icon ? Quickshell.iconPath(e.icon, true) : "" })
        }
        return out
    }
    readonly property string fileName: {
        if (!root.req) return ""
        if (root.req.filename) return root.req.filename
        var u = String(root.req.uri || "")
        var s = u.replace(/[?#].*$/, "").replace(/\/+$/, "")
        var n = s.substring(s.lastIndexOf("/") + 1)
        try { n = decodeURIComponent(n) } catch (e) {}
        return n !== "" ? n : u
    }

    IpcHandler {
        target: "appchooser"
        function open(path: string): string { return root.load(path, false) }
        function update(path: string): string { return root.load(path, true) }
        function close(id: string): string {
            if (root.req && root.req.id === id) root.finish()
            return "ok"
        }
        function ping(id: string): string {
            if (!root.req) return "idle"
            return root.req.id === id ? "open" : "unknown"
        }
        function select(choice: string): string {
            if (!root.req) return "idle"
            root.send({ ok: true, choice: choice })
            return "ok"
        }
        function cancel(): string { root.cancel(); return "ok" }
    }

    FileView { id: reqFile; blockLoading: true; printErrors: false }

    function load(path, keep) {
        reqFile.path = path
        var r = null
        try { r = JSON.parse(reqFile.text()) } catch (e) { r = null }
        reqFile.path = ""
        if (!r || !r.id || r.kind !== "app") return "error: unreadable request"
        if (keep) {
            if (!root.req || root.req.id !== r.id) return "unknown"
            var cur = root.apps[root.sel] ? root.apps[root.sel].id : ""
            root.req = r
            for (var i = 0; i < root.apps.length; i++) if (root.apps[i].id === cur) root.sel = i
            return "ok"
        }
        if (root.req) root.finish()
        root.sel = 0
        root.busy = false
        root.req = r
        return "ok"
    }
    function finish() { root.req = null; root.busy = false }

    Process {
        id: answerProc
        stdout: StdioCollector {
            onStreamFinished: {
                var ok = this.text.trim() === "b true"
                root.busy = false
                if (ok) root.finish()
            }
        }
        onExited: (code, status) => { if (code !== 0) root.busy = false }
    }
    function busArgs(id, json) {
        return ["busctl", "--user", "call", "org.freedesktop.impl.portal.desktop.ewe", "/org/ewe/Portal",
                "org.ewe.Portal1", "Answer", "ss", id, json]
    }
    function send(obj) {
        if (!root.req || root.busy) return
        if (!obj.ok || !obj.choice) { root.cancel(); return }
        root.busy = true
        answerProc.command = root.busArgs(root.req.id, JSON.stringify(obj))
        answerProc.running = true
    }
    function accept() {
        if (root.sel >= 0 && root.sel < root.apps.length) root.send({ ok: true, choice: root.apps[root.sel].id })
    }
    function cancel() {
        if (!root.req) return
        Quickshell.execDetached(root.busArgs(root.req.id, JSON.stringify({ ok: false })))
        root.finish()
    }
    // Komble looks for an app for the type (the same words the gnome-software
    // stand-in hands it); this request ends — the app asks again later
    function findInKomble() {
        var q = String(root.req && root.req.content_type ? root.req.content_type : root.fileName)
        q = q.replace(/^x-scheme-handler\//, "").replace(/^[a-z]+\//, "").replace(/^(x-|vnd\.)/, "")
             .replace(/[+.;].*$/, "").replace(/[^A-Za-z0-9 _-]/g, " ").trim()
        Globals.markLaunch("komble")
        Quickshell.execDetached(q !== "" ? ["komble", "--search=" + q] : ["komble"])
        root.cancel()
    }

    LazyLoader {
        active: root.open
        PanelWindow {
            id: win
            screen: {
                var s = Quickshell.screens, fm = Hyprland.focusedMonitor
                if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
                return s.length > 0 ? s[0] : null
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:app-chooser"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { top: true; bottom: true; left: true; right: true }
            onVisibleChanged: if (visible) focusIn.restart()
            Component.onCompleted: focusIn.restart()
            Timer { id: focusIn; interval: 0; onTriggered: keys.forceActiveFocus() }

            Rectangle { anchors.fill: parent; color: Theme.scrim }
            MouseArea { anchors.fill: parent }   // the scrim does nothing (Dialog)

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(Theme.panelMd, parent.width - 2 * Theme.spaceLg)
                height: Math.min(col.implicitHeight + 2 * Theme.spaceMd, parent.height - 2 * (Theme.spaceXl + Theme.spaceMd))
                radius: Theme.radiusRounded
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                layer.enabled: true
                layer.effect: Elevation {}
                MouseArea { anchors.fill: parent }

                Item {
                    id: keys
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: (ev) => {
                        if (ev.key === Qt.Key_Escape) root.cancel()
                        else if (ev.key === Qt.Key_Down) root.sel = Math.min(root.apps.length - 1, root.sel + 1)
                        else if (ev.key === Qt.Key_Up) root.sel = Math.max(0, root.sel - 1)
                        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) root.accept()
                        else return
                        ev.accepted = true
                    }
                }

                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spaceMd }
                    spacing: Theme.spaceMd

                    Column {
                        width: parent.width
                        spacing: Theme.spaceXs
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: "Open with"
                            color: Theme.textPrimary
                            font.family: Theme.type.h3.family
                            font.pixelSize: Theme.type.h3.size
                            font.weight: Theme.type.h3.weight
                            font.letterSpacing: Theme.type.h3.letterSpacing
                        }
                        TextBody {
                            width: parent.width
                            visible: root.fileName !== ""
                            elide: Text.ElideMiddle
                            color: Theme.textSecondary
                            text: "Choose an app for “" + root.fileName + "”."
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: Math.min(appCol.implicitHeight, 6 * Theme.control2xl)
                        visible: root.apps.length > 0
                        contentHeight: appCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: appCol
                            width: parent.width
                            spacing: Theme.spaceXxs
                            Repeater {
                                model: root.apps
                                Rectangle {
                                    id: appRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool picked: root.sel === appRow.index
                                    width: appCol.width
                                    height: Theme.control2xl
                                    radius: Theme.radiusSecondary
                                    color: appRow.picked ? Theme.accentSubtle : appMa.containsMouse ? Theme.surfaceHover : "transparent"
                                    Image {
                                        id: appImg
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.iconXl; height: Theme.iconXl
                                        sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl
                                        mipmap: true
                                        source: appRow.modelData.icon
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        anchors.centerIn: appImg
                                        visible: !appImg.visible
                                        text: Theme.icApps
                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                                        color: Theme.textSecondary
                                    }
                                    TextBody {
                                        anchors { left: appImg.right; leftMargin: Theme.spaceS + Theme.spaceXs; right: tick.left
                                                  rightMargin: Theme.spaceS; verticalCenter: parent.verticalCenter }
                                        elide: Text.ElideRight
                                        text: appRow.modelData.name
                                        font.weight: appRow.picked ? Theme.fontWeightMedium : Theme.fontWeightRegular
                                    }
                                    Text {
                                        id: tick
                                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: appRow.picked ? Theme.icCheck : ""
                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                        color: Theme.accentText
                                    }
                                    MouseArea {
                                        id: appMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.sel = appRow.index
                                        onDoubleClicked: { root.sel = appRow.index; root.accept() }
                                    }
                                }
                            }
                        }
                    }

                    QsEmpty {
                        width: parent.width
                        visible: root.apps.length === 0
                        ic: Theme.icApps
                        title: "No app opens this yet"
                        desc: Globals.kombleInstalled ? "Komble can find one." : ""
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spaceS + Theme.spaceXs
                        Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                        Item {
                            width: parent.width
                            height: Theme.controlMd
                            QsButton {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                size: "md"; variant: "ghost"; label: "Find an app in Komble…"
                                visible: Globals.kombleInstalled
                                onGo: root.findInKomble()
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceS
                                QsButton { size: "md"; variant: "ghost"; label: "Cancel"; onGo: root.cancel() }
                                QsButton {
                                    size: "md"; variant: "primary"; label: "Open"
                                    disabled: root.apps.length === 0 || root.busy
                                    busy: root.busy
                                    onGo: root.accept()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
