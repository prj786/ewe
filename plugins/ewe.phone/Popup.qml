import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.phone — the phone in the dock. A button in the dock (manifest
// `dockItem`, drawn by the dock plugin; hidden while no phone is paired,
// lit while this card is open) opens a card above it:
//
//   head    the phone's name, its battery, in reach or not; Mirror screen
//           and Open ewe Mobile (only where `ewe-mobile` is installed)
//   Apps    search + a grid of the phone's apps with their real icons (the
//           C2 cache the bridge keeps). Click opens (here when adb is up,
//           else on the phone — ewe Mobile decides); right-click: Open here /
//           Open on the phone. A phone that is away shows the cached grid,
//           dimmed, with the reason opening is off.
//   Files   one click mounts the phone and opens the folder in ewe Files:
//           Camera, Screenshots, Downloads, Documents, Music, Movies, the
//           internal storage.
//
// Keyboard: type to search · arrows move · Enter opens (Shift: on the phone,
// Ctrl: here) · Tab flips Apps / Files · Esc clears the search, then closes.
Scope {
    id: root
    property string pluginId: ""
    property string pluginDir: ""
    property string stateDir: ""
    property var settings: ({})

    readonly property string actionName: "ewe.phone.toggle"

    property string tab: "apps"          // apps | files
    property string query: ""
    property int sel: 0                  // keyboard selection (apps: grid index, files: row index)
    property string pending: ""          // a Files row waiting for the mount
    readonly property int cols: 5

    // ── what the card has to say ───────────────────────────────────────────
    readonly property var dev: Phone.device
    readonly property bool reach: !!root.dev && root.dev.isPaired && root.dev.isReachable
    readonly property var da: Phone.deviceApps
    readonly property var allApps: root.da ? root.da.apps : []
    // none: no phone · stock: the phone does not run ewe Mobile · empty: ewe Mobile, list not here yet
    // away: cached grid of a phone out of reach · ok
    readonly property string appsState: {
        if (!root.dev) return "none"
        if (!root.da || !root.da.ewe) return root.reach ? "stock" : "away-none"
        if (!root.reach) return "away"
        if (root.allApps.length === 0) return "empty"
        return "ok"
    }
    readonly property bool away: root.appsState === "away"
    readonly property bool gridShown: root.appsState === "ok" || root.appsState === "away"
    readonly property var shown: {
        var q = root.query.trim().toLowerCase()
        var src = root.allApps
        if (q === "") return src
        var out = []
        for (var i = 0; i < src.length; i++)
            if (src[i].name.toLowerCase().indexOf(q) >= 0 || src[i].package.toLowerCase().indexOf(q) >= 0) out.push(src[i])
        return out
    }
    readonly property real dimmed: Theme.opacityGlass * Theme.opacityApp

    function ago(ms) {
        if (!ms) return ""
        var m = Math.round((Date.now() - ms) / 60000)
        if (m < 1) return "just now"
        if (m < 60) return m + " min ago"
        var h = Math.round(m / 60)
        if (h < 24) return h + (h === 1 ? " hour ago" : " hours ago")
        var d = Math.round(h / 24)
        return d + (d === 1 ? " day ago" : " days ago")
    }
    readonly property string subtitle: {
        if (!root.dev) return ""
        var b = root.dev.batteryCharge >= 0 ? root.dev.batteryCharge + "%" + (root.dev.isCharging ? " charging" : "") + " · " : ""
        return b + (root.reach ? "In reach" : "Out of reach")
    }

    // ── Files ───────────────────────────────────────────────────────────────
    readonly property var folderDefs: [
        { key: "camera", label: "Camera", glyph: Theme.icCamera },
        { key: "screenshots", label: "Screenshots", glyph: Theme.icImage },
        { key: "downloads", label: "Downloads", glyph: Theme.icDownload },
        { key: "documents", label: "Documents", glyph: Theme.icFileText },
        { key: "music", label: "Music", glyph: Theme.icMusic },
        { key: "movies", label: "Movies", glyph: Theme.icVideo },
        { key: "storage", label: "Internal storage", glyph: Theme.icDrive }
    ]
    readonly property var st: Phone.deviceStorage
    readonly property bool mounted: !!root.st && root.st.state === "mounted"
    readonly property bool mounting: !!root.st && root.st.state === "mounting"
    function pathFor(key) {
        if (!root.mounted) return ""
        var f = root.st.folders
        for (var i = 0; i < f.length; i++) if (f[i].key === key) return f[i].path
        return ""
    }
    function pickFolder(key) {
        if (!root.reach || root.mounting) return
        if (root.mounted) {
            var p = root.pathFor(key)
            if (p !== "") { Phone.openFolder(p); pop.close() }
            return
        }
        root.pending = key
        Phone.mountStorage()
    }
    Connections {
        target: Phone
        function onStorageByDeviceChanged() {
            if (root.pending === "") return
            var s = Phone.deviceStorage
            if (!s) return
            if (s.state === "mounted") {
                var k = root.pending
                root.pending = ""
                root.pickFolder(k)
            } else if (s.state === "error") {
                root.pending = ""
            }
        }
    }

    // ── actions ─────────────────────────────────────────────────────────────
    function openApp(pkg, where) {
        if (!root.reach) return
        Phone.openApp(pkg, where)
        pop.close()
    }
    function setTab(t) {
        root.tab = t
        root.sel = 0
        if (t === "files") { Phone.queryStorage(); catcher.forceActiveFocus() }
        else field.forceActiveFocus()
    }
    function activate(ev) {
        if (root.tab === "apps") {
            var a = root.shown[root.sel]
            if (a) root.openApp(a.package, (ev.modifiers & Qt.ShiftModifier) ? "phone" : (ev.modifiers & Qt.ControlModifier) ? "here" : "auto")
        } else {
            root.pickFolder(root.folderDefs[root.sel].key)
        }
    }
    // one key handler for the search field and the catcher behind it
    function key(ev) {
        if (ctx.open && ctx.handleKey(ev)) { ev.accepted = true; return }
        var k = ev.key
        if (k === Qt.Key_Escape) {
            if (root.query !== "") { root.query = ""; field.text = ""; root.sel = 0 } else pop.close()
            ev.accepted = true
        } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            root.setTab(root.tab === "apps" ? "files" : "apps"); ev.accepted = true
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.activate(ev); ev.accepted = true
        } else if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down) {
            var n = root.tab === "apps" ? root.shown.length : root.folderDefs.length
            var d = k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : k === Qt.Key_Up ? -root.cols : root.cols
            if (root.tab === "files") { if (k === Qt.Key_Left || k === Qt.Key_Right) { ev.accepted = true; return } d = k === Qt.Key_Up ? -1 : 1 }
            if (n > 0) root.sel = Math.max(0, Math.min(n - 1, root.sel + d))
            ev.accepted = true
        } else if (root.tab === "files" && ev.text.length === 1 && ev.text >= " " && !(ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            // typing on Files starts a search on Apps
            root.setTab("apps")
            root.query = ev.text; field.text = ev.text; field.cursorPosition = field.text.length
            ev.accepted = true
        }
    }

    // ── open / close ────────────────────────────────────────────────────────
    function toggleAt(a) { pop.toggleAt(a) }
    readonly property bool paired: Phone.anyPaired
    onPairedChanged: Shell.setDockItemShown("ewe.phone", root.paired)
    Component.onCompleted: {
        Shell.registerAction(root.actionName, function (a) { root.toggleAt(a) })
        Shell.setDockItemShown("ewe.phone", root.paired)
    }
    Component.onDestruction: { Shell.registerAction(root.actionName, null); Shell.setDockItemShown("ewe.phone", true) }

    IpcHandler {
        target: "ewe.phone"
        function toggle(): void { pop.toggleAt(null) }
        function show(): void { pop.openAt(null) }
        function hide(): void { pop.close() }
        function tab(name: string): void { root.setTab(name === "files" ? "files" : "apps") }
        function search(text: string): void { root.setTab("apps"); field.text = text }
        function pick(key: string): void { root.pickFolder(key) }      // a Files row, as a click would
    }

    ContextMenu { id: ctx; name: "phone-menu"; takesKeyboard: false }
    Connections { target: pop; function onOpenChanged() { if (!pop.open) ctx.close() } }

    BarPopup {
        id: pop
        name: "phone"
        owner: "ewe.phone"
        action: root.actionName
        glyph: Theme.icPhone
        title: root.dev ? root.dev.name : "Phone"
        subtitle: root.subtitle
        implicitWidth: Theme.grow(Theme.panelMd)
        exclusiveKeyboard: true
        onOpened: {
            root.query = ""; field.text = ""; root.sel = 0; root.pending = ""
            root.setTab(root.tab)
            if (root.reach && root.da && root.da.ewe) Phone.refreshApps()
        }

        headActions: [
            QsIconButton {
                visible: Phone.eweMobileInstalled && root.reach
                ic: Theme.icShare; tip: "Mirror screen"
                onGo: { Phone.mirror(); pop.close() }
            },
            QsIconButton {
                visible: Phone.eweMobileInstalled
                ic: Theme.icExternal; tip: "Open ewe Mobile"
                onGo: { Phone.openEweMobile("phone"); pop.close() }
            }
        ]

        // keys land here when the search field does not hold the focus
        Item {
            id: catcher
            Keys.onPressed: function (ev) { root.key(ev) }
        }

        QsSegmented {
            options: [{ label: "Apps", value: "apps" }, { label: "Files", value: "files" }]
            value: root.tab
            onPicked: function (v) { root.setTab(v) }
        }

        // ── Apps ──
        Column {
            width: parent.width
            spacing: Theme.spaceS
            visible: root.tab === "apps"

            QsField {
                visible: root.gridShown
                focused: field.activeFocus
                Glyph {
                    id: mag
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.spaceS
                    text: Theme.icSearch; color: Theme.textMuted
                }
                QsFieldInput {
                    id: field
                    anchors.left: mag.right; anchors.right: clearBtn.left
                    anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceXs
                    anchors.verticalCenter: parent.verticalCenter
                    placeholder: "Search " + (root.dev ? root.dev.name : "apps")
                    onTextChanged: { root.query = field.text; root.sel = 0 }
                    Keys.onPressed: function (ev) { root.key(ev) }
                }
                QsIconButton {
                    id: clearBtn
                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceXxs
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text !== ""
                    ic: Theme.icClose; tip: "Clear"
                    onGo: { field.text = ""; field.forceActiveFocus() }
                }
            }

            QsNote {
                visible: root.away
                text: "“" + (root.dev ? root.dev.name : "Your phone") + "” is out of reach, so its apps cannot open. This is the list from "
                      + root.ago(root.da ? root.da.updated : 0) + ". Wake the phone and put it on this network."
            }
            QsNote { visible: Phone.openNote !== "" && root.gridShown; tone: "danger"; text: Phone.openNote }

            GridView {
                id: grid
                visible: root.gridShown && root.shown.length > 0
                width: parent.width
                readonly property int cellW: Math.floor(width / root.cols)
                readonly property int cellH: Theme.icon3xl + Theme.spaceXs + Math.ceil(Theme.type.caption.size * 2.6) + Theme.spaceS
                height: cellH * 4
                cellWidth: cellW; cellHeight: cellH
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.shown
                currentIndex: root.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool cur: root.sel === cell.index
                    width: grid.cellW; height: grid.cellH
                    radius: Theme.radiusPrimary
                    color: cellMa.pressed ? Theme.surfacePressed : (cellMa.containsMouse || cell.cur) ? Theme.surfaceHover : "transparent"
                    border.color: cell.cur ? Theme.focusRing : "transparent"
                    border.width: Theme.focusWidth
                    opacity: root.away ? root.dimmed : 1
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spaceXs
                        spacing: Theme.spaceXs
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Theme.icon3xl; height: Theme.icon3xl
                            Image {
                                anchors.fill: parent
                                visible: cell.modelData.icon !== "" && status === Image.Ready
                                source: cell.modelData.icon !== "" ? "file://" + cell.modelData.icon : ""
                                sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl
                                asynchronous: true; mipmap: true
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: cell.modelData.icon === ""
                                radius: Theme.radiusRounded
                                color: Theme.surfaceHover
                                Glyph { anchors.centerIn: parent; text: Theme.icApps; font.pixelSize: Theme.iconXl }
                            }
                        }
                        Text {
                            width: parent.width
                            text: cell.modelData.name
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                            color: root.away ? Theme.textDisabled : Theme.textPrimary
                            font.family: Theme.type.caption.family
                            font.pixelSize: Theme.type.caption.size
                        }
                    }
                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: root.away ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: function (m) {
                            root.sel = cell.index
                            if (m.button === Qt.RightButton) {
                                var pkg = cell.modelData.package
                                ctx.items = [
                                    { header: cell.modelData.name },
                                    { label: "Open here", icon: Theme.icComputer, disabled: !root.reach, note: Phone.eweMobileInstalled ? "" : "needs ewe Mobile",
                                      action: function () { root.openApp(pkg, "here") } },
                                    { label: "Open on the phone", icon: Theme.icPhone, disabled: !root.reach,
                                      action: function () { root.openApp(pkg, "phone") } }
                                ]
                                ctx.openAt(cell, m.x, m.y)
                            } else {
                                root.openApp(cell.modelData.package, "auto")
                            }
                        }
                    }
                }
            }

            QsEmpty {
                visible: root.gridShown && root.shown.length === 0
                ic: Theme.icSearchOff
                title: "No apps match “" + root.query + "”"
                desc: "Check the spelling, or clear the search."
            }
            QsEmpty {
                visible: root.appsState === "stock"
                ic: Theme.icPhone
                title: "No apps from this phone yet"
                desc: "Install ewe Mobile on your phone to see its apps here."
            }
            QsEmpty {
                visible: root.appsState === "empty"
                ic: Theme.icApps
                title: "Waiting for the phone’s apps"
                desc: "ewe Mobile on the phone sends them as soon as it can. Keep it unlocked for a moment."
                QsButton { variant: "secondary"; label: "Ask again"; onGo: Phone.refreshApps() }
            }
            QsEmpty {
                visible: root.appsState === "away-none"
                ic: Theme.icPhone
                title: "Your phone is out of reach"
                desc: "Wake it and put it on this network. Its apps show here once it has been in reach with ewe Mobile."
            }
            QsEmpty {
                visible: root.appsState === "none"
                ic: Theme.icPhone
                title: "No phone paired"
                desc: "Pair your phone from the Mobile page of Quick settings."
                QsButton { variant: "secondary"; label: "Open Mobile"; onGo: { pop.close(); Shell.openQuickSettings("mobile") } }
            }
        }

        // ── Files ──
        Column {
            width: parent.width
            spacing: Theme.spaceXs
            visible: root.tab === "files"

            QsNote {
                visible: !root.reach && !!root.dev
                text: "“" + (root.dev ? root.dev.name : "Your phone") + "” is out of reach. Wake it and put it on this network to open its files."
            }
            Row {
                visible: root.mounting
                spacing: Theme.spaceS
                Spinner { anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                TextBody { anchors.verticalCenter: parent.verticalCenter; text: "Connecting to your phone…"; color: Theme.textSecondary }
            }
            QsNote {
                visible: !!root.st && root.st.state === "error"
                tone: "danger"
                text: root.st ? root.st.message : ""
            }
            Repeater {
                model: root.dev ? root.folderDefs : []
                delegate: Rectangle {
                    id: fr
                    required property var modelData
                    required property int index
                    readonly property bool missing: root.mounted && root.pathFor(fr.modelData.key) === ""
                    readonly property bool usable: root.reach && !root.mounting && !fr.missing
                    readonly property bool cur: root.sel === fr.index
                    width: parent.width
                    height: Theme.controlXl
                    radius: Theme.radiusPrimary
                    color: frMa.pressed && fr.usable ? Theme.surfacePressed : ((frMa.containsMouse && fr.usable) || fr.cur) ? Theme.surfaceHover : "transparent"
                    border.color: fr.cur ? Theme.focusRing : "transparent"
                    border.width: Theme.focusWidth
                    Glyph {
                        id: fg
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.spaceS + Theme.spaceXs
                        text: fr.modelData.glyph; font.pixelSize: Theme.iconLg
                        color: fr.usable ? Theme.accentText : Theme.textDisabled
                    }
                    TextBody {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: fg.right; anchors.leftMargin: Theme.spaceS
                        anchors.right: chev.left; anchors.rightMargin: Theme.spaceS
                        text: fr.modelData.label
                        color: fr.usable ? Theme.textPrimary : Theme.textDisabled
                        elide: Text.ElideRight
                    }
                    TextCaption {
                        visible: fr.missing
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                        text: "Not on this phone"
                    }
                    Spinner {
                        visible: root.pending === fr.modelData.key && root.mounting
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                        size: Theme.iconSm
                    }
                    Glyph {
                        id: chev
                        visible: fr.usable
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                        text: Theme.icChevronRight; color: Theme.textMuted
                    }
                    MouseArea {
                        id: frMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: fr.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { root.sel = fr.index; root.pickFolder(fr.modelData.key) }
                    }
                }
            }
            QsButton {
                visible: !!root.st && root.st.state === "error" && root.reach
                variant: "secondary"; label: "Try again"
                onGo: Phone.mountStorage()
            }
            QsNote { visible: root.mounted; text: "Opens in ewe Files." }
        }
    }
}
