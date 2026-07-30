import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth

// Bar — the topbar. One bar per monitor. All colours and fonts are
// pulled from Theme.qml (the single source of truth), solid (no glass).
Scope {
    id: bar

    property bool barVisible: true

    // Colours & fonts come entirely from Theme.qml (single source of truth).
    function g(code) { return String.fromCodePoint(code) }   // Nerd Font glyph (handles MDI > U+FFFF)
    function appClass() {
        var t = Hyprland.activeToplevel
        // lastIpcObject.class is the richest source but can lag a focus change /
        // be momentarily empty — fall back to the Wayland appId so the label
        // doesn't blank out. Empty only on the true bare desktop.
        var c = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : ""
        if (!c && t && t.wayland && t.wayland.appId) c = t.wayland.appId
        return c
    }
    function appName() {
        var c = bar.appClass()
        if (!c) return ""
        var s = c.split('.').pop().split('-')[0]
        return s.charAt(0).toUpperCase() + s.slice(1)
    }
    // Icon of the focused app's desktop entry — "" when there is none, so the
    // bar can fall back to the bold name text (icon-instead-of-name design).
    function appIcon() {
        var e = DesktopEntries.heuristicLookup(bar.appClass())
        return (e && e.icon) ? Quickshell.iconPath(e.icon, true) : ""
    }
    // Lua config: /dispatch evaluates its arg as Lua, so we pass typed
    // hl.dsp.* dispatcher expressions (a plain "fullscreen 0" would be invalid Lua).
    function act(expr) { Hyprland.dispatch(expr) }
    function newWindow() {
        var e = DesktopEntries.heuristicLookup(bar.appClass())
        if (e) e.execute()
    }

    // ── IPC: Super+Shift+B → qs ipc call bar toggle ───────────────────────
    IpcHandler {
        target: "bar"
        function toggle(): void { bar.barVisible = !bar.barVisible }
        function show(): void { bar.barVisible = true }
        function hide(): void { bar.barVisible = false }
    }

    // ── clock (shared, 12-hour like the old waybar) ───────────────────────
    property string clockText: ""
    function updateClock() { bar.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM   hh:mm AP") }
    // Tick on the minute, not every second — the format only shows minutes, so a
    // 1 s timer was 86,400 wakeups a day for the 1,440 that change anything. Each
    // tick re-aims at the next minute boundary, so it stays in step with the
    // wall clock instead of drifting.
    Timer {
        id: clockTimer
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            bar.updateClock()
            clockTimer.interval = 60000 - (Date.now() % 60000)
        }
    }

    // ── network state: VPN active → Globals.vpnActive, Wi-Fi connected → wifiUp,
    //    wired (ethernet) connected → wiredUp (shown when no Wi-Fi, e.g. VMs) ──
    //
    // This was a 5 s timer firing FOUR processes — ~170k spawns a day, of which
    // the wifi and wired ones ran the identical nmcli query and the keyboard one
    // duplicated an event we already receive. `nmcli monitor` is a single
    // long-lived process that prints a line whenever NetworkManager changes
    // anything, so we now re-query only when the world actually moves.
    property bool wifiUp: false
    property bool wiredUp: false
    Process {
        id: vpnProc
        running: true                     // one read at startup; nmcli monitor drives the rest
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE connection show --active 2>/dev/null | awk -F: '($1 ~ /vpn|wireguard|tun/) && $2==\"activated\"{print \"yes\"; exit}'"]
        stdout: StdioCollector { onStreamFinished: Globals.vpnActive = (this.text.trim() === "yes") }
    }
    // one query answers both wifi and wired — they used to be two identical calls
    Process {
        id: devProc
        running: true
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$2==\"connected\"{print $1}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = "\n" + this.text.trim() + "\n"
                bar.wifiUp = t.indexOf("\nwifi\n") >= 0
                bar.wiredUp = t.indexOf("\nethernet\n") >= 0
            }
        }
    }
    function netRefresh() {
        vpnProc.running = false; vpnProc.running = true
        devProc.running = false; devProc.running = true
    }
    // NM emits a burst of lines per transition — coalesce them into one re-query
    Timer { id: netDebounce; interval: 400; onTriggered: bar.netRefresh() }
    Process {
        id: netMon
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: function (line) { bar._netMonTries = 0; netDebounce.restart() } }
        // if NetworkManager isn't running, nmcli monitor exits immediately — back
        // off and stop rather than respawning it forever (the bug the KDE Connect
        // bridge used to have). Any successful line resets the counter below.
        onExited: {
            if (bar._netMonTries >= 5) { Log.warn("bar", "nmcli monitor keeps exiting — network indicators are static"); return }
            bar._netMonTries++
            netMonRestart.interval = 5000 * bar._netMonTries
            netMonRestart.restart()
        }
    }
    property int _netMonTries: 0
    Timer { id: netMonRestart; interval: 5000; onTriggered: netMon.running = true }

    // ── keyboard layout indicator (US ↔ GE) ───────────────────────────────
    property string kbLayout: "US"
    property string kbDevice: ""
    function shortLayout(name) {
        var n = (name || "").toLowerCase()
        if (n.indexOf("georg") >= 0) return "GE"
        if (n.indexOf("english") >= 0 || n.indexOf("us") >= 0) return "US"
        return (name || "??").slice(0, 2).toUpperCase()
    }
    Process {
        id: kbProc
        running: true          // one read at startup — `activelayout` below is the live source
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text), kbs = d.keyboards || []
                    for (var i = 0; i < kbs.length; i++) {
                        if (kbs[i].main) { bar.kbDevice = kbs[i].name; bar.kbLayout = bar.shortLayout(kbs[i].active_keymap); break }
                    }
                } catch (e) {}
            }
        }
    }
    // live update: Hyprland emits `activelayout>>keyboard,LayoutName` on every switch
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                var p = event.data.split(",")
                bar.kbLayout = bar.shortLayout(p[p.length - 1])
            }
        }
    }

    // ── a status glyph button: no hover box, just a pointer cursor and a
    //    full-bar-height click target (only the control-centre group highlights). ──
    component StatusItem: Item {
        id: si
        property string glyph: ""
        property color fg: Theme.fgSecondary
        property int fontPx: 15
        signal activated()
        signal secondary()
        signal tertiary()
        signal scrolled(real dy)
        implicitWidth: lbl.implicitWidth + 18
        height: parent ? parent.height : 30
        Text {
            id: lbl
            anchors.centerIn: parent
            text: si.glyph
            color: si.fg
            font.family: Theme.fontMono
            font.pixelSize: si.fontPx
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: function (m) {
                if (m.button === Qt.RightButton) si.secondary()
                else if (m.button === Qt.LeftButton) si.activated()
            }
            // middle-click fires on press — onClicked is unreliable for the
            // middle button (wheel-press / trackpad taps often aren't "clicks").
            onPressed: function (m) {
                if (m.button === Qt.MiddleButton) si.tertiary()
            }
            onWheel: function (w) { si.scrolled(w.angleDelta.y) }
        }
    }

    // ── an inline window-action button (left cluster): a short WORD, not a
    //    glyph (only Close stays an icon — see the row in the bar). ──
    component ActionBtn: Item {
        id: ab
        property string label: ""
        signal triggered()
        width: abLbl.implicitWidth + 16
        height: parent ? parent.height : 30
        Rectangle {
            anchors.centerIn: parent; width: parent.width; height: 22; radius: 6
            color: abMa.containsMouse ? Theme.hover : "transparent"
        }
        Text {
            id: abLbl
            anchors.centerIn: parent
            text: ab.label
            color: abMa.containsMouse ? Theme.fg : Theme.fgSecondary
            font.family: Theme.fontText
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: abMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ab.triggered()
        }
    }

    // ── one bar per monitor ───────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: bar.barVisible
            color: "transparent"
            implicitHeight: 30
            exclusiveZone: bar.barVisible ? 30 : 0
            WlrLayershell.namespace: "quickshell:bar"
            anchors { top: true; left: true; right: true }

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.stroke
                }

                // ── LEFT: workspace chip, then the focused app: icon (falls back
                //    to the bold name when the desktop entry has no icon) + window
                //    title + the inline window actions New · Float · Move⌄ · ✕
                //    (move-to is the one dropdown left — AppMenu.qml). ──
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // current workspace id — always shown; click opens the overview
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 6
                        color: wsMa.containsMouse ? Theme.hover : "transparent"
                        border.color: Theme.stroke; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                            color: Theme.accent
                            font.family: Theme.fontText; font.pixelSize: 12; font.weight: Font.Bold
                        }
                        MouseArea {
                            id: wsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Globals.overviewOpen = !Globals.overviewOpen
                        }
                    }

                    // everything window-related hides on a bare desktop
                    Row {
                    spacing: 8
                    height: parent.height
                    visible: bar.appName() !== ""

                    // app icon — or the bold name when no icon exists
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: bar.appIcon() !== "" ? 20 : nameLbl.implicitWidth
                        height: parent.height
                        Image {
                            anchors.centerIn: parent
                            visible: bar.appIcon() !== ""
                            width: 18; height: 18
                            source: bar.appIcon()
                            sourceSize.width: 36; sourceSize.height: 36
                        }
                        Text {
                            id: nameLbl
                            anchors.verticalCenter: parent.verticalCenter
                            visible: bar.appIcon() === ""
                            text: bar.appName()
                            color: Theme.fg
                            font.family: Theme.fontText; font.pixelSize: 13; font.weight: Font.Bold
                        }
                    }
                    // window title (dim, secondary)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Hyprland.activeToplevel && Hyprland.activeToplevel.title ? Hyprland.activeToplevel.title : ""
                        color: Theme.fgDim
                        font.family: Theme.fontText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 420)
                    }
                    // thin separator before the actions
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 13; color: Theme.fgSecondary; opacity: 0.25 }

                    ActionBtn { label: "New";   onTriggered: bar.newWindow() }
                    ActionBtn { label: "Float"; onTriggered: bar.act('hl.dsp.window.float({action="toggle"})') }
                    // move to workspace — opens the workspace dropdown under itself
                    Item {
                        id: moveToBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: mvRow.implicitWidth + 16
                        height: parent.height
                        Rectangle { anchors.centerIn: parent; width: parent.width; height: 22; radius: 6; color: (mvMa.containsMouse || Globals.appMenuOpen) ? Theme.hover : "transparent" }
                        Row {
                            id: mvRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Move"; color: (mvMa.containsMouse || Globals.appMenuOpen) ? Theme.fg : Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronDown; font.family: Theme.fontMono; font.pixelSize: 7; color: Theme.fgSecondary }
                        }
                        MouseArea {
                            id: mvMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Globals.appAnchorX = moveToBtn.mapToItem(null, 0, 0).x; Globals.appMenuOpen = !Globals.appMenuOpen }
                        }
                    }
                    // close — the one icon in the group, at its right end
                    Item {
                        width: 26
                        height: parent.height
                        Rectangle {
                            anchors.centerIn: parent; width: 24; height: 22; radius: 6
                            color: clMa.containsMouse ? Theme.danger : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icClose
                            color: clMa.containsMouse ? Theme.accentText : Theme.fgSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: clMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.act("hl.dsp.window.close()")
                        }
                    }
                    }
                }

                // (Workspace switching moved to the bottom dock — no centre module here.)

                // ── RIGHT: status cluster ──
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    // system tray
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 11
                        Repeater {
                            model: SystemTray.items
                            delegate: Item {
                                id: trayDelegate
                                required property var modelData
                                width: 18; height: win.height
                                Image {
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: modelData.icon
                                    sourceSize.width: 32; sourceSize.height: 32
                                }
                                // Open the app's context menu (SNI DBusMenu) in our own
                                // themed popup (TrayMenu.qml), anchored under the icon.
                                function openMenu() {
                                    Globals.trayMenuHandle = trayDelegate.modelData.menu
                                    Globals.trayMenuAnchorX = trayDelegate.mapToItem(null, trayDelegate.width / 2, 0).x
                                    Globals.trayMenuOpen = true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    onClicked: function (m) {
                                        var it = trayDelegate.modelData
                                        if (m.button === Qt.RightButton) {
                                            if (it.hasMenu) trayDelegate.openMenu()
                                        } else if (m.button === Qt.MiddleButton) {
                                            it.secondaryActivate()
                                        } else {
                                            // left-click: primary activate; menu-only items
                                            // (Steam, 1Password) have no activate → show menu
                                            if (it.onlyMenu && it.hasMenu) trayDelegate.openMenu()
                                            else it.activate()
                                        }
                                    }
                                    onWheel: function (w) { trayDelegate.modelData.scroll(w.angleDelta.y, false) }
                                }
                            }
                        }
                    }

                    // thin separator between the tray and the action buttons
                    Rectangle {
                        visible: SystemTray.items.values.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 13; color: Theme.fgSecondary; opacity: 0.25
                    }

                    // screenshot (camera) — Left: region · Right: whole screen · Middle: a window
                    StatusItem {
                        glyph: Theme.icCamera        // camera
                        fontPx: 14
                        onActivated: Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/screenshot.sh\" region"])
                        onSecondary: Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/screenshot.sh\" full"])
                        onTertiary:  Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/screenshot.sh\" activewindow"])
                    }

                    // clipboard history + emoji picker (scissors) — opens its popup
                    StatusItem {
                        id: scissorsItem
                        glyph: Theme.icClipboard        // scissors
                        fg: Globals.clipboardOpen ? Theme.fg : Theme.fgSecondary
                        fontPx: 14
                        onActivated: { Globals.clipAnchorX = scissorsItem.mapToItem(null, scissorsItem.width / 2, 0).x; Globals.clipboardOpen = !Globals.clipboardOpen }
                    }

                    // keyboard layout — plain text (US / GE); click cycles the layout
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: kbLbl.implicitWidth + 16
                        height: parent.height
                        Text {
                            id: kbLbl
                            anchors.centerIn: parent
                            text: bar.kbLayout
                            color: Theme.fgSecondary
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", bar.kbDevice || "current", "next"])
                        }
                    }

                    // thin separator between the action buttons and the control centre
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 13; color: Theme.fgSecondary; opacity: 0.25 }

                    // ── ONE wide Control-Centre button: active services + battery.
                    // Hovering highlights the whole group; click opens the sidebar.
                    Rectangle {
                        id: ctlGroup
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        radius: 8
                        width: ctlRow.implicitWidth + 18
                        color: (ctlMa.containsMouse || Globals.quickSettingsOpen) ? Theme.hover : "transparent"

                        Row {
                            id: ctlRow
                            anchors.centerIn: parent
                            spacing: 9

                            // Wired / ethernet (shown when a wired link is up and
                            // Wi-Fi isn't — the common case in VMs and on docks)
                            Text {
                                visible: bar.wiredUp && !bar.wifiUp
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icEthernet        // mdi-ethernet
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: Theme.fgSecondary
                            }
                            // Wi-Fi (only when connected)
                            Text {
                                visible: bar.wifiUp
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icWifi
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: Theme.fgSecondary
                            }
                            // Bluetooth (only when adapter on); blue when a device is connected
                            Text {
                                property var adapter: Bluetooth.defaultAdapter
                                property int conn: {
                                    if (!Bluetooth.devices) return 0
                                    var d = Bluetooth.devices.values, n = 0
                                    for (var i = 0; i < d.length; i++) if (d[i].connected) n++
                                    return n
                                }
                                visible: adapter && adapter.enabled
                                anchors.verticalCenter: parent.verticalCenter
                                text: conn > 0 ? Theme.icBluetoothOn : Theme.icBluetooth
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: conn > 0 ? Theme.accent : Theme.fgSecondary
                            }
                            // VPN (only when active) — key glyph, accent colour
                            Text {
                                visible: Globals.vpnActive
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icVpn
                                font.family: Theme.fontMono; font.pixelSize: 14
                                color: Theme.accent
                            }
                            // SSH tunnel (only when one of the Quick Settings
                            // port-forward tunnels is up) — console glyph, accent
                            Text {
                                visible: Globals.sshTunnelUp
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icSsh
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: Theme.accent
                            }
                            // Insomnia / keep-awake (only when on) — eye glyph, matches
                            // the control-centre toggle; accent colour
                            Text {
                                visible: Globals.caffeine
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icEye
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: Theme.accent
                            }
                            // Phone (KDE Connect) — only when paired + reachable;
                            // battery % and an accent dot for unread phone notifications
                            Row {
                                visible: KdeConnect.connected
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: phGlyph.implicitWidth; height: phGlyph.implicitHeight
                                    Text {
                                        id: phGlyph
                                        text: Theme.icPhone
                                        font.family: Theme.fontMono; font.pixelSize: 13
                                        color: Theme.fgSecondary
                                    }
                                    Rectangle {
                                        visible: KdeConnect.unreadCount > 0
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.rightMargin: -2; anchors.topMargin: -1
                                        width: 6; height: 6; radius: 3
                                        color: Theme.accent
                                    }
                                }
                                Text {
                                    visible: KdeConnect.connected && KdeConnect.device.batteryCharge >= 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: KdeConnect.connected ? KdeConnect.device.batteryCharge + "%" : ""
                                    font.family: Theme.fontText; font.pixelSize: 11
                                    color: Theme.fgSecondary
                                }
                            }
                            // Mail (Gmail) — envelope + count, only when there is unread mail
                            Row {
                                visible: Google.signedIn && Google.mailUnread > 0
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Theme.icMail
                                    font.family: Theme.fontMono; font.pixelSize: 13
                                    color: Theme.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Google.mailUnread > 99 ? "99+" : String(Google.mailUnread)
                                    font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold
                                    color: Theme.fgSecondary
                                }
                            }
                            // Power profile (leaf · balance · speedometer) — reflects tuned profile
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.icLeaf
                                    : PowerProfiles.profile === PowerProfile.Performance ? Theme.icSpeed
                                    : Theme.icBalance
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: PowerProfiles.profile === PowerProfile.Performance ? Theme.warning
                                     : PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.success
                                     : Theme.fgSecondary
                            }
                            // Battery — icon + always-on percentage
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                property var dev: UPower.displayDevice
                                property real pct: dev ? (dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                                property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                                visible: dev && dev.isLaptopBattery
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.charging ? Theme.icBolt
                                        : parent.pct >= 80 ? Theme.icBattFull
                                        : parent.pct >= 60 ? Theme.icBatt80
                                        : parent.pct >= 40 ? Theme.icBatt50
                                        : parent.pct >= 20 ? Theme.icBatt20
                                        : Theme.icBattEmpty
                                    font.family: Theme.fontMono; font.pixelSize: 13
                                    color: parent.charging ? Theme.success : (parent.pct <= 10 ? Theme.danger : (parent.pct <= 20 ? Theme.warning : Theme.fgSecondary))
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(parent.pct) + "%"
                                    font.family: Theme.fontText; font.pixelSize: 12
                                    color: Theme.fgSecondary
                                }
                            }
                            // thin separator, then the clock — all one button
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 13; color: Theme.fgSecondary; opacity: 0.25 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.clockText
                                color: Theme.fg
                                font.family: Theme.fontText
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: ctlMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Globals.quickSettingsOpen = !Globals.quickSettingsOpen
                        }
                    }
                }
            }
        }
    }
}
