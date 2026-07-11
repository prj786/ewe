import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// AppStore — search + install/remove apps from the Arch official repos + the AUR.
// Installs run in the BACKGROUND (no terminal): clicking an action opens a themed
// sudo-password prompt, the password is handed to sudo via an ASKPASS file (never
// on the command line), and a spinner shows on the button until it finishes.
// The AUR helper (paru) is installed by the setup script (phase 10); the store
// just uses it when present, otherwise it searches the official repos only.
// Themed from Theme.qml.
Scope {
    id: root
    function g(c) { return String.fromCodePoint(c) }
    function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }   // shell single-quote

    property string query: ""
    property var results: []
    property var installed: ({})       // pkg name → true (from `pacman -Qq`)
    property string helper: ""          // "paru" | "yay" | "" (= official repos only via pacman)
    property bool searching: false
    property bool searched: false       // a search has actually completed

    // ── one background operation at a time (gated by the single password prompt) ──
    property string busyId: ""          // pkg id currently being installed/removed ("" = idle)
    property string busyKind: ""        // "install" | "remove"
    property real   busyPct: -1         // 0..1 step progress (-1 = indeterminate, e.g. AUR build)
    property string busyStat: ""        // live status line parsed from pacman/paru output
    property string opError: ""         // last failure message (shown as a banner)
    // pending op awaiting the password
    property string pendId: ""
    property string pendKind: ""
    property bool pwOpen: false
    property string pwText: ""

    function ask(kind, id) {
        if (root.busyId !== "") return            // an op is already running
        root.pendKind = kind; root.pendId = id
        root.opError = ""; root.pwText = ""; root.pwOpen = true
    }
    function cancelAsk() { root.pwOpen = false; root.pwText = ""; root.pendId = ""; root.pendKind = "" }

    // The privileged part of each op. Our own pacman steps use `sudo -A`, which
    // makes sudo read the password from the ASKPASS helper (set up in wrap()).
    // paru runs as the normal user (it refuses root) and calls `sudo` ITSELF —
    // but plain `sudo` only consults SUDO_ASKPASS when invoked with `-A`, so
    // paru's internal `sudo` would otherwise find no terminal and die with
    // "sudo: a password is required" (the exact AUR-install failure). Passing
    // `--sudoflags -A` makes every sudo paru runs use our askpass too, so the
    // whole AUR build+install authenticates non-interactively, no terminal.
    function opBody(kind, id) {
        // --skipreview is paru-only (yay has no PKGBUILD-review step to skip);
        // --sudoflags -A works for both helpers.
        if (kind === "install")
            return root.helper
                ? root.helper + " -S --noconfirm --needed" + (root.helper === "paru" ? " --skipreview" : "") + " --sudoflags '-A' -- " + root.sq(id)
                : "sudo -A pacman -S --noconfirm --needed -- " + root.sq(id)
        // kind === "remove"
        return "sudo -A pacman -Rns --noconfirm -- " + root.sq(id)
    }
    // wrap a body: read the password (one line on stdin), drop it into a 0700
    // ASKPASS helper under XDG_RUNTIME_DIR (tmpfs, user-only), export SUDO_ASKPASS
    // so every sudo in the body authenticates non-interactively, run it, then wipe
    // the helper. Status is the body's status; it never hangs on stdin.
    function opCommand(kind, id) {
        return [
            "IFS= read -r __PW",
            'D=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/hs.XXXXXX") || exit 9',
            'chmod 700 "$D"',
            'printf "%s\\n" "$__PW" > "$D/pw"',
            'cat > "$D/askpass" <<EOF',
            '#!/bin/sh',
            'cat "$D/pw"',
            'EOF',
            'chmod 700 "$D/askpass" "$D/pw"',
            'export SUDO_ASKPASS="$D/askpass"',
            '( ' + root.opBody(kind, id) + ' ); __st=$?',
            'rm -rf "$D"',
            'exit $__st'
        ].join("\n")
    }
    function confirmAsk() {
        if (root.pwText.length === 0 || root.busyId !== "") return
        root.busyKind = root.pendKind
        root.busyId = root.pendId
        root.opError = ""
        root.busyPct = -1; root.busyStat = "Starting…"
        opProc.command = ["sh", "-c", root.opCommand(root.pendKind, root.pendId)]
        opProc.running = false; opProc.running = true
        root.pwOpen = false; root.pendId = ""; root.pendKind = ""
    }

    function doSearch() {
        var q = root.query.trim()
        if (q.length < 2) { root.results = []; root.searching = false; root.searched = false; return }
        root.searching = true
        var tool = root.helper ? root.helper : "pacman"   // paru also searches the AUR
        searchProc.command = ["sh", "-c", tool + ' -Ss --color=never -- "$1" 2>/dev/null | head -80', "sh", q]
        searchProc.running = false; searchProc.running = true
    }
    // live search: fire shortly after the user stops typing (no need to press Enter)
    Timer { id: searchDebounce; interval: 350; onTriggered: root.doSearch() }
    Timer { id: refresh; interval: 1500; onTriggered: { qProc.running = true; helperProc.running = true } }

    // latch monitor on open (avoid focus-follows-mouse surface-remap blink)
    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    Component.onCompleted: { root.openScreen = root.focusedScreen(); helperProc.running = true }

    IpcHandler {
        target: "store"
        function toggle(): void { Globals.launcherOpen = false; Globals.placesOpen = false; Globals.storeOpen = !Globals.storeOpen }
        function show(): void { Globals.storeOpen = true }
        function hide(): void { Globals.storeOpen = false }
    }

    // which AUR helper is available? paru preferred, but many Arch derivatives
    // (CachyOS) ship yay — the installer reuses it (phase 10), so honour it too.
    Process {
        id: helperProc
        command: ["sh", "-c", "command -v paru || command -v yay || true"]
        stdout: StdioCollector { onStreamFinished: { var p = this.text.trim(); root.helper = p ? p.split("/").pop() : "" } }
    }
    // installed-package set (so badges/buttons reflect reality after actions)
    Process {
        id: qProc
        command: ["sh", "-c", "pacman -Qq 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { var m = {}, ls = this.text.split("\n"); for (var i = 0; i < ls.length; i++) if (ls[i].trim()) m[ls[i].trim()] = true; root.installed = m } }
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                // pacman/paru -Ss format: "repo/name version [extra]" then an indented description line.
                var out = [], lines = this.text.split("\n"), cur = null
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i]
                    if (!ln.trim()) continue
                    if (/^\s/.test(ln)) { if (cur) cur.desc = ln.trim(); continue }
                    var m = ln.match(/^([^\/\s]+)\/(\S+)\s+(\S+)(.*)$/)
                    if (m) { if (cur) out.push(cur); cur = { source: m[1], id: m[2], name: m[2], ver: m[3], desc: "", inst: /\[installed/.test(m[4]) } }
                }
                if (cur) out.push(cur)
                root.results = out.slice(0, 40)
                root.searching = false; root.searched = true
            }
        }
    }

    // ── the background install/remove process ──
    Process {
        id: opProc
        stdinEnabled: true
        onStarted: { if (root.pwText.length) opProc.write(root.pwText + "\n"); root.pwText = "" }   // one stdin line → ASKPASS file, then drop the in-memory copy
        // Live progress: pacman/paru print "(n/m) installing pkg" lines (and a
        // retrieve phase). We parse the n/m counter into a percentage + status.
        // AUR builds (makepkg) have no counter → indeterminate, labelled "Building".
        stdout: SplitParser {
            onRead: function (line) {
                var s = String(line)
                var m = s.match(/\(\s*(\d+)\/(\d+)\)\s+(\S+)/)
                if (m) {
                    var n = parseInt(m[1]), t = parseInt(m[2])
                    if (t > 0) root.busyPct = Math.max(0, Math.min(1, n / t))
                    root.busyStat = m[3].charAt(0).toUpperCase() + m[3].slice(1) + " " + n + "/" + t
                    return
                }
                if (/Retrieving packages|downloading|Downloading/.test(s)) { root.busyStat = "Downloading…"; root.busyPct = -1; return }
                if (/Making package|Building|makepkg|Starting build/i.test(s)) { root.busyStat = "Building from source…"; root.busyPct = -1; return }
                if (/Resolving dependencies|Synchronizing package|Reading package|looking for conflicting/i.test(s)) { root.busyStat = "Resolving…"; return }
                if (/checking keys|verifying|integrity|checking available/i.test(s)) { root.busyStat = "Verifying…"; return }
            }
        }
        stderr: StdioCollector { id: opErr }
        onExited: function (code, status) {
            if (code === 0) { root.opError = "" }
            else {
                var e = (opErr.text || "").trim().split("\n").filter(function (l) { return l.trim().length }).pop()
                root.opError = "Operation failed. "
                             + (e && e.length ? e : ("exit code " + code + " — wrong password?"))
            }
            root.busyId = ""; root.busyKind = ""; root.busyPct = -1; root.busyStat = ""
            qProc.running = true; helperProc.running = true     // refresh installed set + helper presence
        }
    }

    PanelWindow {
        id: win
        visible: Globals.storeOpen || closeTimer.running
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:store"
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow) }
        Connections { target: Globals; function onStoreOpenChanged() {
            if (Globals.storeOpen) { root.openScreen = root.focusedScreen(); root.query = ""; root.results = []; root.searched = false; root.cancelAsk(); storeIn.text = ""; storeIn.forceActiveFocus(); helperProc.running = true; qProc.running = true }
            else closeTimer.restart()
        } }

        // click-outside closes. A running install/remove keeps going in the
        // BACKGROUND (opProc lives on the Scope, not this window) and the chip
        // re-appears next time the store is opened — so closing is always allowed.
        MouseArea { anchors.fill: parent; onClicked: Globals.storeOpen = false }

        // small reusable spinner
        component Spinner: Item {
            property color ring: Theme.stroke
            property color dot: Theme.accent
            RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: true }
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: parent.ring; border.width: 2 }
            Rectangle { width: parent.width * 0.3; height: width; radius: width / 2; color: parent.dot; anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: -1 }
        }

        Rectangle {
            id: box
            x: Math.max(12, Math.min(parent.width - width - 12, Globals.storeAnchorX - width / 2))
            y: parent.height - height - 90
            width: 460; height: 460
            radius: Theme.radius; color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            opacity: Globals.storeOpen ? 1 : 0
            scale: Globals.storeOpen ? 1 : 0.96
            transformOrigin: Item.BottomLeft
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.shadow; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 8; blurMax: 48 }

            MouseArea { anchors.fill: parent }
            Keys.onEscapePressed: { if (root.pwOpen) root.cancelAsk(); else Globals.storeOpen = false }

            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 12

                // ── header: title (left) + AUR status (right) ──
                Item {
                    // above later siblings so the running-job hover tooltip isn't
                    // clipped behind the search box drawn under it.
                    z: 5
                    width: parent.width; height: 26
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "App Store"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }

                    // AUR helper (paru) is provided by setup — just reflect its presence.
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        // running-job chip: "1 app installing/removing" — hover names it.
                        Rectangle {
                            visible: root.busyId !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: instRow.implicitWidth + 14; height: 18; radius: 9; color: Theme.accent
                            Row { id: instRow; anchors.centerIn: parent; spacing: 5
                                Spinner { width: 10; height: 10; anchors.verticalCenter: parent.verticalCenter; ring: Qt.rgba(1, 1, 1, 0.4); dot: Theme.accentText }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "1 app " + (root.busyKind === "remove" ? "removing" : "installing"); color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.DemiBold }
                            }
                            MouseArea { id: instMa; anchors.fill: parent; hoverEnabled: true }
                            Rectangle {
                                visible: instMa.containsMouse; z: 50
                                anchors.top: parent.bottom; anchors.topMargin: 6; anchors.right: parent.right
                                width: ttT.implicitWidth + 16; height: ttT.implicitHeight + 12
                                radius: 8; color: Theme.elevated; border.color: Theme.stroke; border.width: 1
                                Text { id: ttT; anchors.centerIn: parent; text: (root.busyKind === "remove" ? "Removing " : "Installing ") + root.busyId + "…"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 10 }
                            }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(root.helper !== "" ? 0xF012C : 0xF0159); font.family: Theme.fontMono; font.pixelSize: 12; color: root.helper !== "" ? Theme.accent : Theme.fgDim }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.helper !== "" ? ("AUR · " + root.helper) : "Official repos only"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                    }
                }

                // ── live install/remove progress (background job) ──
                Rectangle {
                    width: parent.width; visible: root.busyId !== ""
                    height: visible ? 46 : 0; radius: Theme.radiusInner; color: Theme.elevated
                    clip: true
                    Column {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 9; spacing: 7
                        Item {
                            width: parent.width; height: 13
                            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - pctT.width - 10; elide: Text.ElideRight
                                text: (root.busyKind === "remove" ? "Removing " : "Installing ") + root.busyId
                                color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Text { id: pctT; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: root.busyStat + (root.busyPct >= 0 ? "  ·  " + Math.round(root.busyPct * 100) + "%" : "")
                                color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                        }
                        // progress track: determinate fill when we have a step count,
                        // otherwise an indeterminate sliding bar.
                        Rectangle {
                            id: track
                            width: parent.width; height: 4; radius: 2; color: Theme.stroke; clip: true
                            Rectangle {
                                id: fill
                                height: parent.height; radius: 2; color: Theme.accent
                                width: root.busyPct >= 0 ? Math.max(6, track.width * root.busyPct) : track.width * 0.32
                                x: root.busyPct >= 0 ? 0 : indet.pos
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            // indeterminate sweep (only runs while pct is unknown)
                            QtObject {
                                id: indet
                                property real pos: 0
                                SequentialAnimation on pos {
                                    running: root.busyId !== "" && root.busyPct < 0
                                    loops: Animation.Infinite
                                    NumberAnimation { from: -track.width * 0.32; to: track.width; duration: 1100; easing.type: Easing.InOutQuad }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 36; radius: Theme.radiusInner
                    color: Theme.bg; border.color: storeIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                    Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontMono; font.pixelSize: 14; color: Theme.fgDim }
                    TextInput {
                        id: storeIn
                        anchors.fill: parent; anchors.leftMargin: 34; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; clip: true
                        enabled: !root.pwOpen
                        onTextChanged: {
                            root.query = text
                            root.searched = false
                            if (text.trim().length < 2) { root.results = []; root.searching = false; searchDebounce.stop() }
                            else searchDebounce.restart()
                        }
                        Keys.onEscapePressed: Globals.storeOpen = false
                        onAccepted: { searchDebounce.stop(); root.doSearch() }
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: storeIn.text.length === 0; text: "Search apps to install or remove…"; color: Theme.fgDim; font: storeIn.font }
                    }
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: (root.helper ? "Searches the official repos + AUR as you type." : "Searches the official repos as you type.") + " Installs run in the background."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }

                // ── error banner ──
                Rectangle {
                    width: parent.width; visible: root.opError !== ""; radius: Theme.radiusInner
                    height: visible ? errT.implicitHeight + 16 : 0; color: Qt.rgba(1, 0.27, 0.23, 0.12); border.color: Theme.danger; border.width: 1
                    Text { id: errT; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8; text: root.opError; wrapMode: Text.WordWrap; color: Theme.danger; font.family: Theme.fontText; font.pixelSize: 10 }
                }

                Flickable {
                    width: parent.width; height: parent.height - y
                    contentHeight: resCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: resCol
                        width: parent.width; spacing: 6
                        // search spinner
                        Row {
                            width: parent.width; height: visible ? 30 : 0; visible: root.searching; spacing: 10
                            Spinner { width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Searching repos + AUR…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        }
                        Text {
                            width: parent.width
                            visible: !root.searching && root.searched && root.results.length === 0 && root.query.trim().length >= 2
                            text: root.helper === "" ? "No results in the official repos. Many apps (e.g. Chrome) are AUR-only — re-run setup to enable the AUR."
                                                      : "No results."
                            wrapMode: Text.WordWrap
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                        }
                        Repeater {
                            model: root.results
                            delegate: Rectangle {
                                id: rowItem
                                required property var modelData
                                readonly property bool aur: modelData.source === "aur"
                                readonly property bool isInstalled: modelData.inst === true || root.installed[modelData.id] === true
                                readonly property bool isBusy: root.busyId === modelData.id
                                width: resCol.width; height: 56; radius: Theme.radiusInner; color: Theme.elevated
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: actions.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Image { anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; sourceSize.width: 60; sourceSize.height: 60; source: Quickshell.iconPath(modelData.name, "application-x-executable") }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 1; width: 230
                                        Row { spacing: 6
                                            Text { text: modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, 150) }
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: badge.implicitWidth + 10; height: 15; radius: 4; color: rowItem.aur ? Theme.accent : Theme.hover
                                                Text { id: badge; anchors.centerIn: parent; text: modelData.source; color: rowItem.aur ? Theme.accentText : Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.DemiBold } }
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: rowItem.isInstalled; text: "installed"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 9 }
                                        }
                                        Text { width: 230; text: modelData.desc; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1 }
                                    }
                                }
                                Row {
                                    id: actions
                                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                    // busy → spinner on this row's button
                                    Rectangle {
                                        visible: rowItem.isBusy; width: 26; height: 26; radius: 7; color: Theme.hover
                                        Spinner { anchors.centerIn: parent; width: 15; height: 15 }
                                    }
                                    // Install (hidden if already installed or busy)
                                    Rectangle { visible: !rowItem.isInstalled && !rowItem.isBusy; width: il.implicitWidth + 16; height: 26; radius: 7
                                        opacity: root.busyId === "" ? 1 : 0.4
                                        color: iMa.containsMouse && root.busyId === "" ? Theme.accent : Theme.hover
                                        Text { id: il; anchors.centerIn: parent; text: "Install"; color: (iMa.containsMouse && root.busyId === "") ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ask("install", modelData.id) } }
                                    // Remove (only if installed, hidden while busy)
                                    Rectangle { visible: rowItem.isInstalled && !rowItem.isBusy; width: rl.implicitWidth + 14; height: 26; radius: 7
                                        opacity: root.busyId === "" ? 1 : 0.4
                                        color: rMa.containsMouse && root.busyId === "" ? Theme.danger : Theme.hover
                                        Text { id: rl; anchors.centerIn: parent; text: "Remove"; color: (rMa.containsMouse && root.busyId === "") ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ask("remove", modelData.id) } }
                                }
                            }
                        }
                    }
                }
            }

            // ════════ in-app sudo password prompt (background auth — no terminal) ════════
            Rectangle {
                anchors.fill: parent; radius: Theme.radius; visible: root.pwOpen
                color: Qt.rgba(0, 0, 0, 0.55)
                MouseArea { anchors.fill: parent; onClicked: root.cancelAsk() }   // click-outside cancels
                Rectangle {
                    anchors.centerIn: parent; width: 320; height: pwCol.implicitHeight + 36
                    radius: Theme.radius; color: Theme.panel; border.color: Theme.stroke; border.width: 1
                    MouseArea { anchors.fill: parent }   // swallow clicks inside the card
                    Column {
                        id: pwCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 18; spacing: 12
                        Text { text: "Administrator password"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.Bold }
                        Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                            text: (root.pendKind === "remove" ? "Remove " : "Install ") + (root.pendId || "") + (root.pendKind === "install" && root.helper ? "  (repos + AUR)" : "") }
                        Rectangle {
                            width: parent.width; height: 38; radius: Theme.radiusInner
                            color: Theme.bg; border.color: pwIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                            TextInput {
                                id: pwIn
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password; passwordCharacter: "•"
                                color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; clip: true
                                onTextChanged: root.pwText = text
                                Keys.onEscapePressed: root.cancelAsk()
                                onAccepted: { if (root.pwText.length) root.confirmAsk() }
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: pwIn.text.length === 0; text: "sudo password"; color: Theme.fgDim; font: pwIn.font }
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            Rectangle { width: cl.implicitWidth + 22; height: 30; radius: 8; color: clMa.containsMouse ? Theme.hover : Theme.elevated
                                Text { id: cl; anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                MouseArea { id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelAsk() } }
                            Rectangle { width: ol.implicitWidth + 22; height: 30; radius: 8; opacity: root.pwText.length ? 1 : 0.4
                                color: Theme.accent
                                Text { id: ol; anchors.centerIn: parent; text: root.pendKind === "remove" ? "Remove" : "Install"; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.pwText.length) root.confirmAsk() } } }
                        }
                    }
                    // clear + focus the field whenever the prompt opens
                    Connections { target: root; function onPwOpenChanged() { if (root.pwOpen) { pwIn.text = ""; pwIn.forceActiveFocus() } } }
                }
            }
        }
    }
}
