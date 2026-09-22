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

    // bar visibility lives in Globals.barVisible so full-screen surfaces
    // (Overview) can reserve space for the bar only while it is shown

    // Colours & fonts come entirely from Theme.qml (single source of truth).
    function g(code) { return String.fromCodePoint(code) }   // Nerd Font glyph (handles MDI > U+FFFF)

    // Inside Glass the bar's modules read Theme.bar* (barAccentText,
    // barTextMuted, barHoverFill, barPressedFill): the Glass card's role
    // remap, made once in Theme.
    // ── tray left-click: activate, then bring the app's window forward ─────
    // SNI Activate alone reaches the app, which then asks the compositor to
    // raise its window — and Hyprland ignores that request for a window on
    // another workspace (focus_on_activate is off), so clicking Komble's tray
    // icon from workspace 2 while Komble sat on workspace 4 did nothing
    // visible. activate() stays (it is what re-opens a window an app hid to
    // its tray); when the app already has a Hyprland window, that window is
    // then focused by address, which switches to its workspace.
    function trayActivate(item) {
        item.activate()
        Globals.focusAppWindow([item.id, item.title])
    }
    // Updates: Komble on its Updates page. An open Komble window is brought
    // forward first — `komble --updates` alone only pings the running
    // instance, whose raise request Hyprland ignores on another workspace.
    function openUpdates() {
        if (!Globals.kombleInstalled) { Globals.openStore(); return }
        Globals.focusAppWindow(["komble"])
        Quickshell.execDetached(["komble", "--updates"])
    }

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
    // ── calendar "something is near": a timed event starts within the hour
    //    (or is running right now). Re-checked on every clock tick — a binding
    //    with `new Date()` inside would never re-evaluate on its own. ────────
    readonly property var calSrc: Agenda.events
    onCalSrcChanged: bar.updateCalSoon()
    property bool calSoon: false
    function updateCalSoon() {
        var now = Date.now(), soon = false
        for (var i = 0; i < bar.calSrc.length; i++) {
            var ev = bar.calSrc[i]
            if (!ev || ev.allDay) continue
            var st = new Date(ev.start).getTime()
            // no end at all: treat it as running for an hour (the old `end ||
            // start` fallback plus the one-minute floor for zero-length events
            // read an end-less event as over a minute after it began)
            var en = ev.end ? new Date(ev.end).getTime() : st + 3600000
            if (isNaN(st)) continue
            if (st - now <= 3600000 && now < Math.max(en, st + 60000)) { soon = true; break }
        }
        bar.calSoon = soon
    }

    // ── IPC: Super+Shift+B → qs ipc call bar toggle ───────────────────────
    IpcHandler {
        target: "bar"
        function toggle(): void { Globals.barVisible = !Globals.barVisible }
        function show(): void { Globals.barVisible = true }
        function hide(): void { Globals.barVisible = false }
    }

    // ── clock: date and time as two fields spaceS apart, shown inside the
    //    Quick settings button (Bar card #10) ──────────────────────────────
    //    12-hour, as before: the shell has no 12/24-hour setting yet ────────
    property string clockDate: ""
    property string clockTime: ""
    readonly property string clockText: bar.clockDate + "  " + bar.clockTime
    function updateClock() {
        var now = new Date()
        bar.clockDate = Qt.formatDateTime(now, "ddd dd MMM")
        bar.clockTime = Qt.formatDateTime(now, "hh:mm AP")
        bar.updateCalSoon()
    }
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
        Globals.netEpoch++                  // Quick Settings re-reads its lists on this
    }
    // NM emits a burst of lines per transition — coalesce them into one re-query
    Timer { id: netDebounce; interval: 400; onTriggered: bar.netRefresh() }
    Process {
        id: netMon
        running: true
        // --pdeathsig: dies with the shell even on an abrupt exit(255) — see
        // Screensaver.qml's pactl; nmcli was the other left-over per restart
        command: ["setpriv", "--pdeathsig", "TERM", "--", "nmcli", "monitor"]
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

    // Driven by the wake sequence in Resume.qml — see the ordering rationale
    // there. Both timers are re-aimed by assigning `interval` (which restarts a
    // running Timer's countdown) rather than restart(), which would assign
    // `running` imperatively and break its declarative binding.
    Connections {
        target: Resume
        function onResyncTime() {
            bar.updateClock()
            clockTimer.interval = 60000 - (Date.now() % 60000)
        }
        function onResyncNetwork() {
            // nmcli monitor usually dies with the link it was watching
            bar._netMonTries = 0
            if (!netMon.running) netMon.running = true
            bar.netRefresh()
        }
    }

    // ── keyboard layout indicator (US ↔ GE) ───────────────────────────────
    property string kbLayout: "US"
    property string kbDevice: ""
    // xkb's long names ("English (US)", "Georgian", "Russian") → a two-letter
    // label. By language, never by substring: `indexOf("us")` labelled
    // Russian, Belarusian and Austrian as US (2026-09-20).
    readonly property var layoutCodes: ({
        english: "US", georgian: "GE", russian: "RU", german: "DE", french: "FR", spanish: "ES",
        italian: "IT", ukrainian: "UA", turkish: "TR", polish: "PL", portuguese: "PT", arabic: "AR",
        hebrew: "IL", greek: "GR", dutch: "NL", swedish: "SE", norwegian: "NO", danish: "DK",
        finnish: "FI", czech: "CZ", hungarian: "HU", romanian: "RO", armenian: "AM", azerbaijani: "AZ",
        japanese: "JP", korean: "KR", chinese: "CN", persian: "IR", hindi: "IN", thai: "TH",
        vietnamese: "VN", serbian: "RS", croatian: "HR", slovak: "SK", slovenian: "SI", bulgarian: "BG",
        lithuanian: "LT", latvian: "LV", estonian: "EE", belarusian: "BY", kazakh: "KZ", uzbek: "UZ"
    })
    function shortLayout(name) {
        var n = (name || "").toLowerCase().trim()
        var m = n.match(/^([a-z]+)(?:[^(]*\(([^)]*)\))?/)     // "english (uk, extd.)" → english, "uk, extd."
        var base = m ? m[1] : "", variant = (m && m[2]) ? m[2] : ""
        if (base === "english" && /^(uk|us)\b/.test(variant)) return variant.slice(0, 2).toUpperCase()
        if (bar.layoutCodes[base]) return bar.layoutCodes[base]
        return (n.slice(0, 2) || "??").toUpperCase()
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
                        if (!kbs[i].main) continue
                        bar.kbDevice = kbs[i].name
                        var km = kbs[i].active_keymap || ""
                        if (km !== "" && km.toLowerCase() !== "error") bar.kbLayout = bar.shortLayout(km)
                        break
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
                // data = "keyboard,Layout name" — the name may hold commas
                // ("English (US, intl.)"), the keyboard never does
                var cut = event.data.indexOf(",")
                var name = cut >= 0 ? event.data.slice(cut + 1) : event.data
                // a virtual keyboard (wtype: password fill, emoji) has no
                // keymap name and reports "error" — that showed as "ER".
                // It says nothing about the real layout: ask the main keyboard.
                if (name === "" || name.toLowerCase() === "error") kbProc.running = true
                else bar.kbLayout = bar.shortLayout(name)
            }
        }
    }

    // ── a BAR MODULE (design system: Bar → Module states) ────────────────
    // barModule tall (28 / 32 / 40 by icon size), radiusPrimary, spaceS of
    // side padding, no fill until you point at it. Default glyphs are
    // textSecondary; hover takes surfaceHover and textPrimary, an open popup
    // surfacePressed — inside Glass those are the glass tints, which
    // Theme.barHoverFill / barActive already resolve.
    //
    // Declare content as children (they land centred in a Row, spaceXs
    // apart); `glyph` alone draws one icon and is the common case.
    component BarModule: Item {
        id: si
        property string glyph: ""
        property color fg: Theme.textSecondary
        property int fontPx: Theme.barIcon
        property bool active: false      // its popup is open
        // .ewe-barmod: spaceS of side padding (spaceS + spaceXs on the large
        // bar); a glyph-only module has none and is just barModule square
        property int padH: si.glyph !== "" ? 0 : Theme.barLarge ? Theme.spaceS + Theme.spaceXs : Theme.spaceS
        // the workspace chip's mark: a spaceMd × borderWidth2 accent rule
        // spaceXs above the chip's bottom edge, always on
        property bool underline: false
        default property alias content: inner.data
        readonly property alias hovered: ma.containsMouse
        // each module is a button named with its state (Bar card, Accessibility)
        property string a11yName: ""
        Accessible.role: Accessible.Button
        Accessible.name: si.a11yName
        signal activated()
        signal secondary()
        signal tertiary()
        signal scrolled(real dy)
        implicitWidth: Math.max(Theme.barModule, inner.implicitWidth + 2 * si.padH)
        // barModule, or taller when its content is (a larger text size,
        // Georgian) — the bar grows with it
        implicitHeight: Math.max(Theme.barModule, inner.implicitHeight + 2 * Theme.spaceXxs)
        height: implicitHeight
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusPrimary
            color: si.active ? Theme.barPressedFill
                 : ma.containsMouse ? Theme.barHoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        }
        Row {
            id: inner
            anchors.centerIn: parent
            spacing: Theme.spaceXs
            Text {
                visible: si.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: si.glyph
                color: ma.containsMouse && si.fg === Theme.textSecondary ? Theme.textPrimary : si.fg
                font.family: Theme.fontIcons
                font.pixelSize: si.fontPx
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            }
        }
        Rectangle {
            visible: si.underline
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceXs
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.spaceMd; height: Theme.borderWidth2
            radius: Theme.borderWidth2
            color: Theme.accent
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
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

    // ── the bar's own divider: borderWidth1 × iconMd, spaceXs each side ──
    component BarSep: Item {
        implicitWidth: Theme.borderWidth1 + 2 * Theme.spaceXs
        implicitHeight: Theme.barLarge ? Theme.iconLg : Theme.iconMd
        Rectangle {
            anchors.centerIn: parent
            width: Theme.borderWidth1; height: parent.height
            color: Theme.barOutline
        }
    }

    // ── one bar per monitor ───────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: Globals.barVisible
            color: "transparent"
            // the strip plus its rule; nothing floats, so nothing needs room
            // for a shadow (the Bar card gives the bar a line, not one). The
            // strip is its content plus barPadding above and below: the rows
            // report their height through Globals, and Theme.barHeight adds
            // the padding (owner's bar model — the bar follows its icons).
            implicitHeight: Theme.barHeight + Theme.borderWidth1
            Binding {
                target: Globals; property: "barContentHeight"
                value: Math.max(leftRow.implicitHeight, centerSlots.implicitHeight, rightRow.implicitHeight)
                when: win.modelData === Quickshell.screens[0]
            }
            exclusiveZone: Globals.barVisible ? Theme.barHeight : 0
            mask: Region { x: 0; y: 0; width: win.width; height: Theme.barHeight }
            WlrLayershell.namespace: "quickshell:bar"
            anchors { top: true; left: true; right: true }

            Rectangle {
                id: barStrip
                anchors { left: parent.left; right: parent.right }
                height: Theme.barHeight
                // Entrance: slide down from behind the top edge once the shell
                // is up (also plays for a bar spawned on hotplug). Reduce
                // motion turns the slide into a plain fade at durFast.
                // The tokens land a beat after the bar is built, so Reduce
                // motion can turn on while the slide is already running:
                // never STOP it (that parks the bar off-screen) — finish it.
                NumberAnimation on y {
                    readonly property bool rm: Theme.reduceMotion
                    onRmChanged: if (rm) complete()
                    from: -win.implicitHeight; to: 0
                    duration: Theme.reduceMotion ? 0 : Theme.durSlow; easing.type: Theme.easeSlow
                }
                // Entrance fade + the Reduce-motion Overview fade. A BINDING,
                // not a `NumberAnimation on opacity`: a value source owns the
                // property and would leave no way to fade for the Overview.
                property bool entered: false
                Component.onCompleted: barStrip.entered = true
                opacity: !barStrip.entered ? 0
                       : (Theme.reduceMotion && Globals.overviewCover) ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                // The Overview takes the whole screen: the bar slides UP out of
                // view while it is open and comes back after the cards have gone.
                // exclusiveZone is NOT touched (windows must not relayout) —
                // only the visuals move, on a Translate so this never fights the
                // entrance animation above. Reduce motion keeps the target at 0
                // and the fade above does the work, so a reduceMotion flip
                // mid-slide glides the bar home instead of parking it off-screen.
                transform: Translate {
                    y: (Globals.overviewCover && !Theme.reduceMotion) ? -win.implicitHeight : 0
                    Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                }
                // surfaceBase, or glassBase once bar opacity drops below 100
                color: Theme.barGround
                // the bar's edge: a borderWidth1 rule below it (Bar card #1),
                // glassBorder inside Glass so it reads over any wallpaper
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.bottom }
                    height: Theme.borderWidth1
                    color: Theme.barOutline
                }

                // ── LEFT: workspace chip, then the focused app's icon + name —
                //    just identity, no window actions (those live on the window
                //    itself / keybinds now). ──
                Row {
                    id: leftRow
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.barLarge ? Theme.spaceS + Theme.spaceXs : Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceS

                    // ── the workspace chip (design system: Workspace indicator)
                    // A barModule chip carrying the focused workspace's number
                    // with a spaceMd × borderWidth2 accent underline spaceXs
                    // above its bottom edge. The underline is ALWAYS there: it
                    // is what says "this is where you are". Click toggles the
                    // Overview; the full workspace list lives in the dock.
                    BarModule {
                        id: wsChip
                        anchors.verticalCenter: parent.verticalCenter
                        active: Globals.overviewOpen
                        underline: true
                        a11yName: "Workspace " + (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1) + ", open Overview"
                        onActivated: Globals.overviewOpen = !Globals.overviewOpen
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                            color: Theme.textPrimary
                            font.family: Theme.type.bodyStrong.family
                            font.pixelSize: Theme.barLarge ? Theme.fontSizeLg : Theme.fontSizeMd
                            font.weight: Theme.fontWeightSemibold
                            font.features: ({ "tnum": 1 })
                        }
                    }

                    // focused app — its icon and the app's name (from its id,
                    // not the window title), in accentText. Hidden on a bare
                    // desktop.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceS
                        visible: bar.appName() !== ""
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: bar.appIcon() !== ""
                            width: Theme.barIcon; height: Theme.barIcon
                            source: bar.appIcon()
                            sourceSize.width: 2 * Theme.barIcon; sourceSize.height: 2 * Theme.barIcon
                            mipmap: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: bar.appName()
                            color: Theme.barAccentText
                            font.family: Theme.type.bodyStrong.family
                            font.pixelSize: Theme.barLarge ? Theme.fontSizeLg : Theme.fontSizeMd
                            font.weight: Theme.fontWeightSemibold
                        }
                    }

                    // third-party bar widgets whose manifest says defaultSection = left
                    BarPluginSlots { section: "left"; anchors.verticalCenter: parent.verticalCenter }
                }

                // ── CENTRE: no first-party module (workspace switching moved to the
                //    bottom dock) — only plugin widgets that ask for the middle. ──
                BarPluginSlots {
                    id: centerSlots
                    section: "center"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    // yield on a narrow output instead of overlapping the clusters
                    fits: x >= leftRow.x + leftRow.width + Theme.spaceMd
                       && x + width <= rightRow.x - Theme.spaceMd
                }

                // ── RIGHT: status cluster ──
                Row {
                    id: rightRow
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.barLarge ? Theme.spaceS + Theme.spaceXs : Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceXs

                    // system tray, then the plugins' bar widgets (defaultSection =
                    // right, the default) — one row, so a widget sits in the
                    // tray's rhythm: barIcon glyphs, spaceXs apart, the same
                    // gap as every other module in the cluster (Bar card #5)
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXs
                        Row {
                        visible: Globals.barShows("tray") && SystemTray.items.values.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXs
                        Repeater {
                            model: SystemTray.items
                            delegate: Item {
                                id: trayDelegate
                                required property var modelData
                                // a module-sized cell, like the plugins' widgets
                                // beside it: barModule cells spaceXs apart is the
                                // one rhythm of the whole cluster
                                width: Theme.barModule; height: Theme.barModule
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusPrimary
                                    color: trayMa.containsMouse ? Theme.barHoverFill : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                }
                                TrayIcon {
                                    anchors.centerIn: parent
                                    px: Theme.barIcon
                                    source: modelData.icon
                                }
                                // Open the app's context menu (SNI DBusMenu) in our own
                                // themed popup (TrayMenu.qml), anchored under the icon.
                                function openMenu() {
                                    Globals.trayMenuHandle = trayDelegate.modelData.menu
                                    Globals.trayMenuAnchorX = trayDelegate.mapToItem(null, trayDelegate.width / 2, 0).x
                                    Globals.trayMenuOpen = true
                                }
                                MouseArea {
                                    id: trayMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    onClicked: function (m) {
                                        var it = trayDelegate.modelData
                                        if (m.button === Qt.RightButton) {
                                            if (it.hasMenu) trayDelegate.openMenu()
                                        } else if (m.button === Qt.MiddleButton) {
                                            it.activate()   // the app's own Activate (window), for menu-on-left apps
                                        } else {
                                            // left-click: primary activate; menu-only items
                                            // (Steam, 1Password) have no activate → show menu.
                                            // Some Qt apps answer Activate by opening their OWN
                                            // menu as a stray toplevel, which lands centred and
                                            // dead under a layer-shell tray (Nextcloud client,
                                            // metal 2026-09-02) — for those the themed menu is
                                            // the left-click too; middle-click still activates.
                                            var key = String(it.id || it.title || "").toLowerCase()
                                            var menuOnLeft = ["nextcloud"].some(function (k) { return key.indexOf(k) >= 0 })
                                            if (it.hasMenu && (it.onlyMenu || menuOnLeft)) trayDelegate.openMenu()
                                            else bar.trayActivate(it)
                                        }
                                    }
                                    onWheel: function (w) { trayDelegate.modelData.scroll(w.angleDelta.y, false) }
                                }
                            }
                        }
                        }
                        BarPluginSlots { section: "right"; anchors.verticalCenter: parent.verticalCenter }
                    }

                    // tiling ⇄ floating — the icon IS the state (grid = tiling,
                    // stacked windows = floating). Globals.setTiling goes
                    // through ewe-conf, which regenerates user.lua and reloads
                    // Hyprland; the icon follows when the reload poke lands.
                    // Assigning Globals.tilingEnabled here instead only worked
                    // while the Settings panel happened to be loaded.
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Globals.barShows("tiling")
                        glyph: Globals.tilingEnabled ? Theme.icTiling : Theme.icFloating
                        a11yName: Globals.tilingEnabled ? "Tiling, on" : "Tiling, off"
                        onActivated: Globals.setTiling(!Globals.tilingEnabled)
                    }

                    // ── Komble — ALWAYS present, whether or not the app has ever
                    // run: the glyph IS the state. Check = everything current,
                    // accent download + count = updates pending, spinning
                    // arrows-clockwise = an upgrade is running (db.lck held, or
                    // Komble asserting `updates working` through its AUR
                    // builds). Click opens Komble on its Updates page;
                    // middle-click re-checks.
                    BarModule {
                        id: updItem
                        padH: 0            // an icon module (.ewe-barmod--icon)
                        a11yName: updItem.updating ? "Updates, updating"
                                : Globals.updatesTotal > 0 ? "Updates, " + Globals.updatesTotal + " available" : "Updates, up to date"
                        readonly property bool updating: Globals.updatesBusy || Globals.updatesWorking
                        anchors.verticalCenter: parent.verticalCenter
                        onActivated: bar.openUpdates()
                        onTertiary: Globals.checkUpdates()
                        Text {
                            visible: updItem.updating
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icRefresh
                            font.family: Theme.fontIcons
                            font.pixelSize: Theme.barIcon
                            color: Theme.barAccentText
                            RotationAnimation on rotation {
                                running: updItem.updating
                                loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 1400
                            }
                        }
                        BarIcon {
                            visible: !updItem.updating
                            anchors.verticalCenter: parent.verticalCenter
                            // `download` + a count while updates wait, `check`
                            // in textMuted once everything is current
                            glyph: Globals.updatesTotal > 0 ? Theme.icDownload : Theme.icCheck
                            color: Globals.updatesTotal > 0 ? Theme.barAccentText : Theme.barTextMuted
                            count: Globals.updatesTotal
                            centered: true
                        }
                    }

                    // keyboard layout — two capitals (US / GE); click cycles it
                    BarModule {
                        id: kbMod
                        a11yName: "Keyboard layout, " + bar.kbLayout
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Globals.barShows("keyboard")
                        onActivated: Quickshell.execDetached(["hyprctl", "switchxkblayout", bar.kbDevice || "current", "next"])
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: bar.kbLayout
                            color: kbMod.hovered ? Theme.textPrimary : Theme.textSecondary
                            font.family: Theme.type.label.family
                            font.pixelSize: Theme.barLarge ? Theme.fontSizeMd : Theme.fontSizeS
                            font.weight: Theme.fontWeightSemibold
                            font.letterSpacing: Theme.trackingWide * Theme.fontSizeS
                        }
                    }

                    // divider between the action modules and Quick settings —
                    // only while at least one of them is shown
                    BarSep {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Globals.barShows("tiling") || Globals.barShows("keyboard")
                    }

                    // ── the QUICK SETTINGS button (design system: Bar #10).
                    // ONE pill holding every status indicator that applies,
                    // spaceS apart, with spaceS + spaceXs of side padding.
                    // Click opens Quick settings; scrolling changes the volume.
                    BarModule {
                        id: ctlGroup
                        // Module states: textSecondary, textPrimary on hover
                        // or while Quick settings is open
                        a11yName: "Quick settings"
                        readonly property color ink: ctlGroup.hovered || ctlGroup.active ? Theme.textPrimary : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                        padH: Theme.spaceS + Theme.spaceXs
                        active: Globals.quickSettingsOpen
                        onActivated: Globals.quickSettingsOpen = !Globals.quickSettingsOpen
                        // wheel = volume by 3%, mirroring the XF86 keys; the OSD
                        // pops by itself (it observes the default sink)
                        onScrolled: function (dy) {
                            Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0",
                                                     "@DEFAULT_AUDIO_SINK@", dy > 0 ? "3%+" : "3%-"])
                        }

                        Row {
                            id: ctlRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceS

                            // ORDER is the Bar card's, each shown only while it
                            // applies: network busy → keep awake · casting ·
                            // SSH · VPN → sync → notifications · mail ·
                            // calendar · phone → wired/Wi-Fi · sound · mic ·
                            // Bluetooth → power profile · battery.
                            // Metrics are uniform on purpose: every glyph is
                            // Theme.barIcon, every count a Badge, every figure
                            // the caption size — the group reads as one calm
                            // instrument row.

                            // connecting… — spins while a Wi-Fi/VPN attempt
                            // is in flight (Quick Settings drives Globals.netBusy)
                            Spinner {
                                visible: Globals.netBusy !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                size: Theme.barIcon
                            }

                            // ── toggler states ──
                            // Insomnia / keep-awake — eye glyph, matches the CC toggle
                            Text {
                                visible: Globals.caffeine
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icEye
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                            }
                            // Cast to TV — screencast glyph while a cast session exists;
                            // accent = picture on glass, dim = still handshaking
                            Text {
                                visible: Globals.casting
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icCast
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: Globals.castState === "streaming" || Globals.castLegacy
                                       ? Theme.barAccentText : ctlGroup.ink
                            }
                            // SSH tunnel (a Quick Settings port-forward is up)
                            Text {
                                visible: Globals.sshTunnelUp
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icSsh
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                            }
                            // VPN (only when active)
                            Text {
                                visible: Globals.vpnActive
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icVpn
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                            }

                            // ewe-sync — the account app's state, so "is my
                            // stuff safe" is answerable from the bar. Hidden
                            // while idle: a green tick that is always there
                            // teaches people to stop reading it, so the bar
                            // only speaks up when syncing or when something
                            // actually needs the user. Click opens ewe-sync.
                            Item {
                                readonly property string st: Globals.syncState
                                readonly property bool busy: st === "syncing"
                                id: syncItem
                                visible: st === "syncing" || st === "conflict" || st === "offline"
                                anchors.verticalCenter: parent.verticalCenter
                                width: visible ? Theme.barIcon : 0
                                height: Theme.barIcon
                                Text {
                                    anchors.centerIn: parent
                                    text: syncItem.busy ? Theme.icRefresh
                                        : syncItem.st === "conflict" ? Theme.icCloudAlert
                                        : Theme.icCloudOff
                                    font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                    color: syncItem.st === "conflict" ? Theme.danger
                                         : syncItem.busy ? Theme.barAccentText : Theme.barTextMuted
                                    RotationAnimation on rotation {
                                        running: syncItem.busy
                                        loops: Animation.Infinite
                                        from: 0; to: 360
                                        duration: 1400
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Globals.openSync()
                                }
                            }

                            // ── comms ──
                            // Notifications — bell + count while the history holds anything
                            BarIcon {
                                visible: count > 0
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: Theme.icBell
                                color: Theme.barAccentText
                                count: Globals.server ? Globals.server.trackedNotifications.values.length : 0
                            }
                            // Mail (IMAP or Gmail) — envelope + count, only when there is unread mail
                            BarIcon {
                                visible: Mail.available && Mail.unread > 0
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: Theme.icMail
                                color: ctlGroup.ink
                                count: Mail.unread
                            }
                            // Calendar — an event is running or starts within the hour
                            Text {
                                visible: bar.calSoon
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icCalendar
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                            }
                            // Phone (KDE Connect) — only when paired + reachable;
                            // battery % and an accent dot for unread phone notifications
                            Row {
                                visible: KdeConnect.connected
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceXs
                                BarIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: Theme.icPhone
                                    color: ctlGroup.ink
                                    // the phone's own count is already on the
                                    // phone — here it only has to say "unread"
                                    count: KdeConnect.unreadCount
                                    dotOnly: true
                                }
                                Text {
                                    visible: KdeConnect.connected && KdeConnect.device.batteryCharge >= 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: KdeConnect.connected ? KdeConnect.device.batteryCharge + "%" : ""
                                    font.family: Theme.type.label.family
                                    font.pixelSize: Theme.barLarge ? Theme.fontSizeMd : Theme.fontSizeS
                                    font.features: ({ "tnum": 1 })
                                    color: ctlGroup.ink
                                }
                            }
                            // Wired / ethernet (shown when a wired link is up and
                            // Wi-Fi isn't — the common case in VMs and on docks)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icEthernet
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                                visible: bar.wiredUp && !bar.wifiUp && Globals.barShows("wifi")
                            }
                            // Wi-Fi (only when connected)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icWifi
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                                visible: bar.wifiUp && Globals.barShows("wifi")
                            }
                            // Sound — always there, between the radios: the level as
                            // volume waves on the built-in speakers, and the DEVICE when
                            // output is somewhere else (headset · headphones · a speaker
                            // box). AudioState reads the sink's own PipeWire properties;
                            // nothing polls.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: AudioState.outputGlyph
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: AudioState.muted && AudioState.outputKind === "internal" ? Theme.barTextMuted : ctlGroup.ink
                                visible: AudioState.sink !== null && Globals.barShows("sound")
                            }
                            // Microphone open — an app has it (a link from the default
                            // source to a stream), in the accent so it reads as "live",
                            // the way a camera light does.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icMic
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: Theme.barAccentText
                                visible: AudioState.micInUse && Globals.barShows("mic")
                            }
                            // Bluetooth (only when adapter on); filled glyph when a device is connected
                            Text {
                                property var adapter: Bluetooth.defaultAdapter
                                property int conn: {
                                    if (!Bluetooth.devices) return 0
                                    var d = Bluetooth.devices.values, n = 0
                                    for (var i = 0; i < d.length; i++) if (d[i].connected) n++
                                    return n
                                }
                                anchors.verticalCenter: parent.verticalCenter
                                text: conn > 0 ? Theme.icBluetoothOn : Theme.icBluetooth
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                                visible: adapter && adapter.enabled && Globals.barShows("bluetooth")
                            }
                            // Power profile (leaf · balance · speedometer) — reflects tuned profile
                            Text {
                                visible: Globals.barShows("power")
                                anchors.verticalCenter: parent.verticalCenter
                                text: PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.icLeaf
                                    : PowerProfiles.profile === PowerProfile.Performance ? Theme.icSpeed
                                    : Theme.icBalance
                                font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                color: ctlGroup.ink
                            }
                            // Battery — icon + always-on percentage
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceXs
                                property var dev: UPower.displayDevice
                                property real pct: dev ? (dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                                property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                                visible: dev && dev.isLaptopBattery && Globals.barShows("battery")
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.charging ? Theme.icBolt
                                        : parent.pct >= 80 ? Theme.icBattFull
                                        : parent.pct >= 60 ? Theme.icBatt80
                                        : parent.pct >= 40 ? Theme.icBatt50
                                        : parent.pct >= 20 ? Theme.icBatt20
                                        : Theme.icBattEmpty
                                    font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
                                    // low battery keeps its alert colours; the bolt glyph
                                    // alone signals charging
                                    color: parent.pct <= 10 && !parent.charging ? Theme.danger
                                         : parent.pct <= 20 && !parent.charging ? Theme.warning
                                         : ctlGroup.ink
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(parent.pct) + "%"
                                    font.family: Theme.type.label.family
                                    font.pixelSize: Theme.barLarge ? Theme.fontSizeMd : Theme.fontSizeS
                                    font.features: ({ "tnum": 1 })
                                    color: ctlGroup.ink
                                }
                            }
                            // the clock — date and time inside the pill, so the
                            // one button holds every status indicator plus the
                            // time (Bar card #10). Tabular figures keep the
                            // digits still; clicking the button opens Quick
                            // settings and the wheel changes the volume, as
                            // they did while the clock sat on its own.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.clockDate
                                color: Theme.textPrimary
                                font.family: Theme.type.bodyStrong.family
                                font.pixelSize: Theme.barLarge ? Theme.fontSizeLg : Theme.fontSizeMd
                                font.weight: Theme.fontWeightSemibold
                                font.features: ({ "tnum": 1 })
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.clockTime
                                color: Theme.textPrimary
                                font.family: Theme.type.bodyStrong.family
                                font.pixelSize: Theme.barLarge ? Theme.fontSizeLg : Theme.fontSizeMd
                                font.weight: Theme.fontWeightSemibold
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }
            }
        }
    }
}
