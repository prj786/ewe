import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// AppStore — search + install/remove apps from the Arch official repos + the AUR,
// the fallback quick installer for a machine without Komble (design system:
// Launcher panel for the panel, App card's row form for the results, Card,
// Dialog, Progress bar, Inline alert). Installs run in the BACKGROUND (no
// terminal): clicking an action opens a password dialog, the password is
// handed to sudo via an ASKPASS file (never on the command line), and a
// spinner shows on the row until it finishes. The AUR helper (paru) is
// installed by the setup script (phase 10); the store just uses it when
// present, otherwise it searches the official repos only. Tokens only.
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
    // Komble (Globals.kombleInstalled) is THE software manager (repos + AUR +
    // AppImages + updates); when present, every store entry point launches it
    // and this panel never opens. It survives only as the fallback quick
    // installer for a machine where the Komble build failed.
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

    // IPC lives in IpcHub.qml (always resident — this panel is lazy-loaded).

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
                root.opError = (root.busyKind === "remove" ? "Couldn’t remove " : "Couldn’t install ") + root.busyId + ". "
                             + (e && e.length ? e : ("The password may be wrong (exit code " + code + ")."))
            }
            root.busyId = ""; root.busyKind = ""; root.busyPct = -1; root.busyStat = ""
            qProc.running = true; helperProc.running = true     // refresh installed set + helper presence
        }
    }

    PanelWindow {
        id: win
        visible: Globals.storeOpen || win.held
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:store"
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + Theme.durFast); onTriggered: win.held = false }
        Connections { target: Globals; function onStoreOpenChanged() {
            if (Globals.storeOpen) { closeTimer.stop(); win.held = true; root.openScreen = root.focusedScreen(); root.query = ""; root.results = []; root.searched = false; root.cancelAsk(); storeIn.text = ""; storeIn.forceActiveFocus(); helperProc.running = true; qProc.running = true }
            else closeTimer.restart()
        } }

        // click-outside closes. A running install/remove keeps going in the
        // BACKGROUND (opProc lives on the Scope, not this window) and its
        // progress is back next time the panel opens — so closing is always allowed.
        MouseArea { anchors.fill: parent; onClicked: Globals.storeOpen = false }

        // ── the parts, in the type styles ──
        component TBody: Text {
            color: Theme.textPrimary
            font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size; font.weight: Theme.type.body.weight
        }
        component TCaption: Text {
            color: Theme.textMuted
            font.family: Theme.type.caption.family; font.pixelSize: Theme.type.caption.size; font.weight: Theme.type.caption.weight
        }
        // Button: primary (accent), secondary (surfaceRaised + borderStrong),
        // ghost, or danger (the danger fill with onStatus ink); sm is
        // controlSm tall, md controlMd
        component Btn: Rectangle {
            id: bt
            property string label: ""
            property string kind: "secondary"      // primary · secondary · ghost · danger
            property string size: "md"
            property bool disabled: false
            property string a11yName: bt.label
            signal go()
            readonly property bool _sm: bt.size === "sm"
            width: btT.implicitWidth + 2 * (bt._sm ? Theme.spaceS : Theme.spaceS + Theme.spaceXs)
            height: bt._sm ? Theme.controlSm : Theme.controlMd
            radius: Theme.radiusPrimary
            color: bt.disabled ? (bt.kind === "ghost" ? "transparent" : Theme.surfaceRaised)
                 : bt.kind === "primary" ? (btMa.pressed ? Theme.accentPressed : btMa.containsMouse ? Theme.accentHover : Theme.accent)
                 : bt.kind === "danger" ? Theme.danger
                 : btMa.pressed ? Theme.surfacePressed : btMa.containsMouse ? Theme.surfaceHover
                 : bt.kind === "ghost" ? "transparent" : Theme.surfaceRaised
            border.width: bt.disabled || bt.kind === "secondary" ? Theme.borderWidth1 : 0
            border.color: bt.disabled ? Theme.borderSubtle : Theme.borderStrong
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            activeFocusOnTab: !bt.disabled
            Accessible.role: Accessible.Button
            Accessible.name: bt.a11yName
            Keys.onSpacePressed: if (!bt.disabled) bt.go()
            Keys.onReturnPressed: if (!bt.disabled) bt.go()
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(Theme.borderWidth1 + Theme.focusWidth)
                radius: Theme.radiusPrimary + Theme.borderWidth1 + Theme.focusWidth
                color: "transparent"; visible: bt.activeFocus
                border.color: Theme.focusRing; border.width: Theme.focusWidth
            }
            Text {
                id: btT
                anchors.centerIn: parent
                text: bt.label
                color: bt.disabled ? Theme.textDisabled : bt.kind === "primary" ? Theme.onAccent
                     : bt.kind === "danger" ? Theme.onStatus : Theme.textPrimary
                font.family: Theme.type.body.family
                font.pixelSize: bt._sm ? Theme.fontSizeS : Theme.fontSizeMd
                font.weight: Theme.fontWeightMedium
            }
            MouseArea { id: btMa; anchors.fill: parent; enabled: !bt.disabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bt.go() }
        }

        Rectangle {
            id: box
            // Launcher panel placement: above the dock's store button, kept
            // spaceS + spaceXs from the screen edges and above the dock
            readonly property int edgeGap: Theme.spaceS + Theme.spaceXs
            readonly property int dockGap: Theme.dockClearance + edgeGap
            x: Math.max(edgeGap, Math.min(parent.width - width - edgeGap, Globals.storeAnchorX - width / 2))
            width: Theme.panelMd
            height: Math.min(Theme.panelMd + Theme.controlXl + Theme.spaceMd + Theme.spaceXs, parent.height - dockGap - 2 * edgeGap)
            radius: Theme.radiusRounded; color: Theme.surfaceRaised
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            opacity: Globals.storeOpen ? 1 : 0
            // a panel opens with a fade plus a short rise from its own edge;
            // Reduce motion zeroes the offset, leaving the fade (Theme)
            y: Math.max(edgeGap, parent.height - height - dockGap) + (Globals.storeOpen ? 0 : Theme.slideOffset)
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            layer.enabled: true
            layer.effect: Elevation {}

            MouseArea { anchors.fill: parent }
            Keys.onEscapePressed: { if (root.pwOpen) root.cancelAsk(); else Globals.storeOpen = false }

            Column {
                anchors.fill: parent; anchors.margins: Theme.spaceS + Theme.spaceXs; spacing: Theme.spaceS + Theme.spaceXs

                // ── header: title, where it searches, Komble ──
                Item {
                    width: parent.width; height: Theme.controlMd
                    Text {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "Install apps"; color: Theme.textPrimary
                        font.family: Theme.type.h4.family; font.pixelSize: Theme.type.h4.size; font.weight: Theme.type.h4.weight
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceS
                        Badge {
                            anchors.verticalCenter: parent.verticalCenter
                            label: root.helper !== "" ? "Repos + AUR" : "Official repos"
                            tone: root.helper !== "" ? "success" : "neutral"; solid: false
                        }
                        // through to the full software manager, when it is installed
                        Btn {
                            visible: Globals.kombleInstalled
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "ghost"; size: "sm"; label: "Open Komble"
                            onGo: { if (!Globals.focusAppWindow(["komble"])) Quickshell.execDetached(["komble"]); Globals.storeOpen = false }
                        }
                    }
                }

                // ── Search field ──
                Rectangle {
                    width: parent.width; height: Theme.controlMd
                    radius: Theme.radiusPrimary; color: Theme.surfaceSunken
                    border.width: Theme.fieldBorderWidth
                    border.color: storeIn.activeFocus ? Theme.focusRing : Theme.borderStrong
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    Text { id: sIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textMuted }
                    TextInput {
                        id: storeIn
                        anchors.left: sIc.right; anchors.leftMargin: Theme.spaceXs; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                        anchors.top: parent.top; anchors.bottom: parent.bottom
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size; clip: true
                        enabled: !root.pwOpen
                        onTextChanged: {
                            root.query = text
                            root.searched = false
                            if (text.trim().length < 2) { root.results = []; root.searching = false; searchDebounce.stop() }
                            else searchDebounce.restart()
                        }
                        Keys.onEscapePressed: Globals.storeOpen = false
                        onAccepted: { searchDebounce.stop(); root.doSearch() }
                        TBody { anchors.verticalCenter: parent.verticalCenter; visible: storeIn.text.length === 0; text: "Search apps"; color: Theme.textMuted }
                    }
                }

                // ── the running install/remove (a Progress bar; the job
                //    keeps going in the background if the panel closes) ──
                Column {
                    width: parent.width; spacing: Theme.spaceXs; visible: root.busyId !== ""
                    Item {
                        width: parent.width; height: Theme.lineHeightS
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - pctT.width - Theme.spaceS; elide: Text.ElideRight
                            text: (root.busyKind === "remove" ? "Removing " : "Installing ") + root.busyId + "…"
                            color: Theme.textPrimary
                            font.family: Theme.type.label.family; font.pixelSize: Theme.type.label.size; font.weight: Theme.type.label.weight
                        }
                        Text {
                            id: pctT
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            visible: root.busyPct >= 0
                            text: Math.round(root.busyPct * 100) + "%"
                            color: Theme.textSecondary
                            font.family: Theme.type.monoNumeric.family; font.pixelSize: Theme.type.monoNumeric.size; font.weight: Theme.type.monoNumeric.weight
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    // the track: determinate fill when there is a step count,
                    // otherwise an indeterminate sweep
                    Rectangle {
                        id: track
                        width: parent.width; height: Theme.spaceXs; radius: Theme.radiusFull; color: Theme.surfaceHover; clip: true
                        Rectangle {
                            height: parent.height; radius: Theme.radiusFull; color: Theme.accent
                            width: root.busyPct >= 0 ? Math.max(height, track.width * root.busyPct) : track.width / 3
                            x: root.busyPct >= 0 ? 0 : indet.pos
                            Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                        }
                        // indeterminate sweep (only runs while pct is unknown).
                        // Its period has no token (reported); Reduce motion
                        // makes it three times slower (Progress bar card).
                        QtObject {
                            id: indet
                            property real pos: 0
                            readonly property int period: Theme.reduceMotion ? 3300 : 1100
                            SequentialAnimation on pos {
                                running: root.busyId !== "" && root.busyPct < 0
                                loops: Animation.Infinite
                                NumberAnimation { from: -track.width / 3; to: track.width; duration: indet.period; easing.type: Easing.InOutCubic }
                            }
                        }
                    }
                    TCaption { width: parent.width; text: root.busyStat; elide: Text.ElideRight }
                }

                // ── an error: a danger Inline alert ──
                Rectangle {
                    width: parent.width; visible: root.opError !== ""; radius: Theme.radiusPrimary
                    height: visible ? errT.implicitHeight + 2 * Theme.spaceS : 0
                    color: Theme.dangerSubtle
                    Text { id: errIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.top: parent.top; anchors.topMargin: Theme.spaceS + Theme.borderWidth1; text: Theme.icWarning; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.danger }
                    TBody { id: errT; anchors.left: errIc.right; anchors.leftMargin: Theme.spaceS; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs; anchors.top: parent.top; anchors.topMargin: Theme.spaceS; text: root.opError; wrapMode: Text.WordWrap }
                }

                Flickable {
                    width: parent.width; height: parent.height - y
                    contentHeight: resCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: resCol
                        width: parent.width; spacing: Theme.spaceXxs
                        // before a search: what this panel does
                        Column {
                            width: parent.width; spacing: Theme.spaceXxs
                            visible: !root.searching && root.query.trim().length < 2
                            TBody { width: parent.width; text: "Search to install or remove an app"; wrapMode: Text.WordWrap }
                            TCaption { width: parent.width; wrapMode: Text.WordWrap
                                text: (root.helper ? "Searches the official repos and the AUR as you type." : "Searches the official repos as you type.") + " Installs run in the background." }
                        }
                        // searching
                        Row {
                            width: parent.width; height: visible ? Theme.controlLg : 0; visible: root.searching; spacing: Theme.spaceS
                            Spinner { anchors.verticalCenter: parent.verticalCenter }
                            TBody { anchors.verticalCenter: parent.verticalCenter; text: root.helper ? "Searching the repos and the AUR…" : "Searching the repos…"; color: Theme.textSecondary }
                        }
                        // no results (Empty state)
                        Column {
                            width: parent.width; spacing: Theme.spaceXxs
                            visible: !root.searching && root.searched && root.results.length === 0 && root.query.trim().length >= 2
                            TBody { width: parent.width; text: "No apps match “" + root.query.trim() + "”"; wrapMode: Text.WordWrap }
                            TCaption { width: parent.width; wrapMode: Text.WordWrap
                                text: root.helper === "" ? "Many apps, Chrome among them, are only in the AUR. Run the setup again to turn it on." : "Try another name." }
                        }
                        // the results: App card rows
                        Repeater {
                            model: root.results
                            delegate: Rectangle {
                                id: rowItem
                                required property var modelData
                                readonly property bool aur: modelData.source === "aur"
                                readonly property bool isInstalled: modelData.inst === true || root.installed[modelData.id] === true
                                readonly property bool isBusy: root.busyId === modelData.id
                                width: resCol.width; height: Theme.control2xl + Theme.spaceS
                                radius: Theme.radiusSecondary
                                color: rowMa.containsMouse ? Theme.surfaceHover : "transparent"
                                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true }
                                Image {
                                    id: appIc
                                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.icon2xl; height: Theme.icon2xl
                                    sourceSize.width: 2 * Theme.icon2xl; sourceSize.height: 2 * Theme.icon2xl; mipmap: true
                                    source: Quickshell.iconPath(rowItem.modelData.name, "application-x-executable")
                                }
                                Column {
                                    anchors.left: appIc.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                                    anchors.right: actions.left; anchors.rightMargin: Theme.spaceS
                                    anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXxs
                                    Row {
                                        width: parent.width; spacing: Theme.spaceXs
                                        TBody { id: nameT; anchors.verticalCenter: parent.verticalCenter; text: rowItem.modelData.name; font.weight: Theme.fontWeightMedium; elide: Text.ElideRight
                                                width: Math.min(implicitWidth, parent.width - srcB.width - parent.spacing - (instB.visible ? instB.width + parent.spacing : 0)) }
                                        // App card "Sources": the repo neutral, the AUR warning (built from source)
                                        Badge { id: srcB; anchors.verticalCenter: parent.verticalCenter; label: rowItem.modelData.source; tone: rowItem.aur ? "warning" : "neutral"; solid: false }
                                        Badge { id: instB; anchors.verticalCenter: parent.verticalCenter; visible: rowItem.isInstalled; label: "Installed"; tone: "success"; solid: false }
                                    }
                                    TCaption { width: parent.width; text: rowItem.modelData.desc; elide: Text.ElideRight; maximumLineCount: 1 }
                                }
                                Row {
                                    id: actions
                                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXs
                                    Spinner { visible: rowItem.isBusy; anchors.verticalCenter: parent.verticalCenter }
                                    Btn {
                                        visible: !rowItem.isInstalled && !rowItem.isBusy
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "primary"; size: "sm"; label: "Install"; a11yName: "Install " + rowItem.modelData.name
                                        disabled: root.busyId !== ""
                                        onGo: root.ask("install", rowItem.modelData.id)
                                    }
                                    Btn {
                                        visible: rowItem.isInstalled && !rowItem.isBusy
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "secondary"; size: "sm"; label: "Remove"; a11yName: "Remove " + rowItem.modelData.name
                                        disabled: root.busyId !== ""
                                        onGo: root.ask("remove", rowItem.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ════════ the password Dialog (background auth — no terminal) ════════
            Rectangle {
                anchors.fill: parent; radius: Theme.radiusRounded; visible: root.pwOpen
                color: Theme.scrim
                MouseArea { anchors.fill: parent }   // the scrim does nothing: work isn't lost by a stray click
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    height: pwCol.implicitHeight + 2 * Theme.spaceMd
                    radius: Theme.radiusRounded; color: Theme.surfaceRaised
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    MouseArea { anchors.fill: parent }   // swallow clicks inside the card
                    Column {
                        id: pwCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: Theme.spaceMd; spacing: Theme.spaceMd
                        Column {
                            width: parent.width; spacing: Theme.spaceXs
                            Text { width: parent.width; wrapMode: Text.WordWrap
                                text: (root.pendKind === "remove" ? "Remove " : "Install ") + (root.pendId || "") + "?"
                                color: Theme.textPrimary
                                font.family: Theme.type.h3.family; font.pixelSize: Theme.type.h3.size; font.weight: Theme.type.h3.weight }
                            TBody { width: parent.width; wrapMode: Text.WordWrap; color: Theme.textSecondary
                                text: "Enter your password to change the system." + (root.pendKind === "install" && root.helper ? " It is built from the AUR if it isn’t in the repos." : "") }
                        }
                        Rectangle {
                            width: parent.width; height: Theme.controlMd; radius: Theme.radiusPrimary
                            color: Theme.surfaceSunken
                            border.width: Theme.fieldBorderWidth
                            border.color: pwIn.activeFocus ? Theme.focusRing : Theme.borderStrong
                            TextInput {
                                id: pwIn
                                anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS; verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password; passwordCharacter: "•"
                                color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size; clip: true
                                onTextChanged: root.pwText = text
                                Keys.onEscapePressed: root.cancelAsk()
                                onAccepted: { if (root.pwText.length) root.confirmAsk() }
                                TBody { anchors.verticalCenter: parent.verticalCenter; visible: pwIn.text.length === 0; text: "Password"; color: Theme.textMuted }
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: Theme.spaceS
                            Btn { kind: "ghost"; label: "Cancel"; onGo: root.cancelAsk() }
                            Btn {
                                kind: root.pendKind === "remove" ? "danger" : "primary"
                                label: (root.pendKind === "remove" ? "Remove " : "Install ") + (root.pendId || "")
                                disabled: root.pwText.length === 0
                                onGo: { if (root.pwText.length) root.confirmAsk() }
                            }
                        }
                    }
                    // clear + focus the field whenever the prompt opens
                    Connections { target: root; function onPwOpenChanged() { if (root.pwOpen) { pwIn.text = ""; pwIn.forceActiveFocus() } } }
                }
            }
        }
    }
}
