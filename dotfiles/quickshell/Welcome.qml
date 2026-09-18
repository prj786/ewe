import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Welcome — what a stranger sees in their first minute (ROADMAP 0.7).
// Shown ONCE on a fresh install (stamp: ~/.local/state/ewe/welcomed), never
// on the live ISO (EWE_LIVE — the installer is the point there). Six steps:
//   1 welcome · 2 get online (0.9.16-2) · 3 updates (0.9.19: a fresh install
//   must be current before anything can be installed — the sync database it
//   was born with points at packages the mirrors have already dropped) ·
//   4 sign in to your Nextcloud (RFC-005 — the ewe account) · 5 restore offer
//   (only when the account holds a backup from another machine) · 6 the
//   60-second tour. Google is not on this screen at all.
// Re-open any time:  qs ipc call welcome toggle   (reset: … welcome reset)
//
// 0.9.16-2, the first bare-metal install: this overlay sat on the Overlay
// layer above EVERYTHING — Quick settings (so no Wi-Fi could be joined
// to reach the sign-in step), the keyring prompt and the browser it had just
// asked for. It now carries its own network step and steps aside while a
// sign-in is in flight.
// 2026-09-03: a floating card, not a sheet. The dimmed backdrop is gone and the
// input region is the card alone (`mask`), so the desktop behind stays live
// and nothing else on screen is swallowed. The card's height also no longer
// animates between steps — a centred card grows from both edges at once, so
// every step visibly walked up and down.
//
// Design system: Welcome, Step indicator, Wi-Fi picker.
//
//   card    panelLg wide, surfaceRaised with a borderWidth1 borderSubtle
//           outline, the radiusRounded corner and shadowFloat
//   body    spaceLg of padding, spaceMd between things, centred: an icon4xl
//           accentSubtle glyph tile with an icon2xl accentText glyph (or the
//           sheep mark on the first step), the h2 title, body-lg text in
//           textSecondary and label notes in textMuted
//   footer  above a borderWidth1 divider: six dots — the current one a
//           spaceMd accent pill, the done ones textSecondary, the rest
//           borderStrong — then a ghost and a primary Button
Scope {
    id: root

    property bool open: false
    property int step: 0
    readonly property string stamp: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ewe/welcomed"
    readonly property int stepNetwork: 1
    readonly property int stepUpdates: 2
    readonly property int stepSignIn: 3
    readonly property int stepRestore: 4
    readonly property int stepTour: 5
    readonly property bool isLive: (Quickshell.env("EWE_LIVE") || "") !== ""

    // ── updates ──
    // checking | current | pending | installing | done | failed | unknown
    property string updState: "unknown"
    property int updCount: 0
    property var updTail: []             // the last few lines of pacman's output
    readonly property bool updBusy: updState === "checking" || updState === "installing"
    function checkUpdates() {
        root.updState = "checking"; root.updCount = 0; root.updTail = []
        updCheck.running = false; updCheck.running = true
    }
    function installUpdates() {
        if (root.updState === "installing") return
        root.updState = "installing"; root.updTail = []
        updInstall.running = false; updInstall.running = true
    }
    function _updLine(line) {
        var l = String(line).replace(/\r/g, "").trim()
        if (l === "") return
        var t = root.updTail.slice(); t.push(l.length > 96 ? l.slice(0, 96) + "…" : l)
        while (t.length > 5) t.shift()
        root.updTail = t
    }
    // pacman-contrib's checkupdates: 0 = updates listed on stdout, 2 = none
    property Process updCheck: Process {
        command: ["checkupdates"]
        stdout: StdioCollector { id: updOut }
        onExited: function (code) {
            if (code === 2) { root.updState = "current"; updAdvance.restart(); return }
            if (code !== 0) { root.updState = "unknown"; return }   // no checkupdates / no network: not a blocker
            var n = updOut.text.split("\n").filter(function (l) { return l.trim() !== "" }).length
            root.updCount = n
            if (n === 0) { root.updState = "current"; updAdvance.restart() } else root.updState = "pending"
        }
    }
    // the shell's own PolkitAgent (Auth.qml) answers pkexec's prompt
    property Process updInstall: Process {
        command: ["pkexec", "pacman", "-Syu", "--noconfirm", "--noprogressbar"]
        stdout: SplitParser { onRead: function (data) { root._updLine(data) } }
        stderr: SplitParser { onRead: function (data) { root._updLine(data) } }
        onExited: function (code) {
            if (code === 0) { root.updState = "done"; root.updCount = 0; updAdvance.restart() }
            else if (code === 126 || code === 127) { root.updState = "failed"; root._updLine("Authentication was cancelled — nothing was changed.") }
            else root.updState = "failed"
        }
    }
    Timer { id: updAdvance; interval: 2200; onTriggered: if (root.open && root.step === root.stepUpdates) root.next() }
    onStepChanged: {
        if (root.step === root.stepUpdates) {
            if (!root.online || root.isLive) { root.step = root.stepSignIn; return }
            if (root.updState !== "done") root.checkUpdates()
        }
    }

    // a restore is worth offering when the account has a backup and THIS
    // machine has never synced — the same rule Cloud._maybeOfferRestore uses
    readonly property bool restoreWorthIt: Cloud.signedIn && Cloud.cloudInfo !== null && Cloud.lastSync === ""
    readonly property bool online: wifi.online
    // the browser and the keyring prompt must be clickable: get out of the way
    readonly property bool yielding: Cloud.busy === "signin"

    onOpenChanged: Globals.welcomeOpen = root.open

    function finish() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && : > "$1"', "sh", root.stamp])
        root.open = false
    }
    function next() {
        if (root.step === root.stepUpdates && root.updBusy) return                                        // never skip past a running upgrade
        if (root.step === root.stepSignIn && !root.restoreWorthIt) { root.step = root.stepTour; return }   // nothing to restore → tour
        if (root.step >= root.stepTour) { root.finish(); return }
        root.step += 1
    }

    // first start: no stamp + not the live ISO → open after the desktop settled
    property Process _probe: Process {
        running: true
        command: ["sh", "-c", '[ -n "$EWE_LIVE" ] && exit 1; [ -e "$1" ] && exit 1; exit 0', "sh", root.stamp]
        onExited: function (code) { if (code === 0) openDelay.restart() }
    }
    Timer { id: openDelay; interval: 2500; onTriggered: { root.step = 0; root.open = true } }

    IpcHandler {
        target: "welcome"
        function toggle(): void { root.step = 0; root.open = !root.open }
        function hide(): void { root.open = false }
        function reset(): void { Quickshell.execDetached(["rm", "-f", root.stamp]); root.step = 0; root.open = true }
        function step(n: int): void { root.open = true; root.step = n }   // driver screenshots
    }

    // the network step (WifiPicker, inside the card below) polls only while
    // it is on screen; once online, move on by itself after a beat — long
    // enough to read "Connected"
    Timer { id: autoAdvance; interval: 1800; onTriggered: if (root.open && root.step === root.stepNetwork && wifi.online) root.next() }

    // sign-in landed while the account step is up → show "signed in as …" for
    // a beat, learn whether the account holds a backup, then move on
    Connections {
        target: Cloud
        function onSignedInChanged() {
            if (root.open && root.step === root.stepSignIn && Cloud.signedIn) Cloud.checkCloud(function (ok) { signedInAdvance.restart() })
        }
        function onSyncStateChanged() {
            if (root.open && root.step === root.stepRestore && root._restoring && Cloud.syncState !== "syncing") { root._restoring = false; root.step = root.stepTour }
            if (root._backingUp && Cloud.syncState !== "syncing") root._backingUp = false
        }
    }
    Timer { id: signedInAdvance; interval: 1600; onTriggered: if (root.open && root.step === root.stepSignIn && Cloud.signedIn) root.next() }
    property bool _restoring: false
    property bool _backingUp: false

    PanelWindow {
        id: win
        // yield while a sign-in runs: the keyring prompt and the browser open
        // as ordinary toplevels UNDER an Overlay-layer surface, and this one
        // used to swallow every click on them — "the keyring never showed up"
        visible: (root.open || win.held) && !root.yielding
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:welcome"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: (root.open && !root.yielding) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        // a floating card, not a sheet: only the card takes input, so the
        // desktop behind it stays live (and the keyring prompt stays clickable)
        mask: Region { item: card }

        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections { target: root; function onOpenChanged() { if (root.open) { closeTimer.stop(); win.held = true; keys.forceActiveFocus() } else closeTimer.restart() } }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: if (!root.updBusy) root.finish()
            Keys.onReturnPressed: if ((root.step !== root.stepNetwork || root.online) && !root.updBusy) root.next()
            Keys.onEnterPressed: if ((root.step !== root.stepNetwork || root.online) && !root.updBusy) root.next()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Theme.panelLg
            height: body.implicitHeight
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1
            layer.enabled: true
            layer.effect: Elevation {}
            // fade plus a slideOffset lift, in at durBase and out at durFast
            opacity: root.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.open ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            transform: Translate {
                y: (root.open || Theme.reduceMotion) ? 0 : Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
            MouseArea { anchors.fill: parent }

            // ── shared bits ──
            component Title: Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                color: Theme.textPrimary
                font.family: Theme.type.h2.family
                font.pixelSize: Theme.type.h2.size
                font.weight: Theme.type.h2.weight
                font.letterSpacing: Theme.type.h2.letterSpacing
            }
            component Body: Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.family: Theme.type.bodyLg.family
                font.pixelSize: Theme.type.bodyLg.size
            }
            component Note: Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                color: Theme.textMuted
                font.family: Theme.type.label.family
                font.pixelSize: Theme.fontSizeS
            }
            // the system Button: ghost by default, primary when it carries the
            // step's own verb
            component Btn: Rectangle {
                id: b
                property string label: ""
                property bool primary: false
                property bool enabled: true
                signal go()
                width: bt.implicitWidth + 2 * Theme.spaceMd
                height: Theme.controlLg
                radius: Theme.radiusPrimary
                color: !b.enabled ? Theme.surfaceRaised
                     : b.primary ? (bMa.pressed ? Theme.accentPressed
                                  : bMa.containsMouse ? Theme.accentHover : Theme.accent)
                     : (bMa.pressed ? Theme.surfacePressed
                       : bMa.containsMouse ? Theme.surfaceHover : "transparent")
                border.color: b.enabled ? "transparent" : Theme.borderSubtle
                border.width: Theme.borderWidth1
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Text {
                    id: bt
                    anchors.centerIn: parent; text: b.label
                    color: !b.enabled ? Theme.textDisabled : b.primary ? Theme.onAccent : Theme.textPrimary
                    font.family: Theme.type.body.family
                    font.pixelSize: Theme.type.body.size
                    font.weight: Theme.fontWeightMedium
                }
                MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; cursorShape: Qt.PointingHandCursor; onClicked: b.go() }
            }
            component LinkBtn: Text {
                property string label: ""
                signal go()
                text: label; color: Theme.accentText
                font.family: Theme.type.label.family
                font.pixelSize: Theme.type.label.size
                font.weight: Theme.fontWeightSemibold
                MouseArea { anchors.fill: parent; anchors.margins: -Theme.spaceXs; cursorShape: Qt.PointingHandCursor; onClicked: parent.go() }
            }
            component Glyph: Rectangle {
                property string ic: ""
                width: Theme.icon4xl; height: Theme.icon4xl
                radius: Theme.radiusRounded
                color: Theme.accentSubtle
                Text {
                    anchors.centerIn: parent; text: parent.ic
                    font.family: Theme.fontIcons; font.pixelSize: Theme.icon2xl
                    color: Theme.accentText
                }
            }
            component TourRow: Row {
                property string ic: ""
                property string head: ""
                property string text: ""
                width: parent.width; spacing: Theme.spaceS + Theme.spaceXs
                Rectangle {
                    width: Theme.controlXl; height: Theme.controlXl
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    Text {
                        anchors.centerIn: parent; text: parent.parent.ic
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                        color: Theme.textPrimary
                    }
                }
                Column {
                    width: parent.width - Theme.controlXl - parent.spacing
                    spacing: Theme.spaceXxs
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width; text: parent.parent.head
                        color: Theme.textPrimary
                        font.family: Theme.type.bodyStrong.family
                        font.pixelSize: Theme.type.bodyStrong.size
                        font.weight: Theme.fontWeightSemibold
                    }
                    Text {
                        width: parent.width; text: parent.parent.text
                        color: Theme.textSecondary
                        font.family: Theme.type.label.family
                        font.pixelSize: Theme.fontSizeS
                        wrapMode: Text.Wrap
                    }
                }
            }

            // the card is one Column: the step's body with its own padding,
            // then the footer full-bleed under a divider
            Column {
                id: body
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: parent.border.width
                spacing: 0

            Column {
                id: steps
                x: Theme.spaceLg
                width: parent.width - 2 * Theme.spaceLg
                topPadding: Theme.spaceLg
                bottomPadding: Theme.spaceMd
                spacing: Theme.spaceMd

                // ── 1 · welcome ──
                Column {
                    visible: root.step === 0
                    width: parent.width; spacing: Theme.spaceMd
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: Qt.resolvedUrl("assets/logo.png")
                        width: Theme.icon4xl + Theme.spaceLg; height: width
                        sourceSize.width: 2 * width; sourceSize.height: 2 * width
                        fillMode: Image.PreserveAspectFit; mipmap: true
                    }
                    Title { text: "Welcome to ewe" }
                    Body { text: "A clean, dark desktop that stays out of your way.\nA few short steps and it is yours." }
                }

                // ── 2 · get online ──
                Column {
                    visible: root.step === root.stepNetwork
                    width: parent.width; spacing: Theme.spaceMd
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; ic: Theme.icWifi }
                    Title { text: "Connect to the internet" }
                    Body { text: "The next steps bring the system up to date and sign you in to your Nextcloud, which can bring a backup down to this machine — all of that needs a connection. A cable just works; Wi-Fi is joined right here." }
                    WifiPicker {
                        id: wifi
                        width: parent.width
                        active: root.open && root.step === root.stepNetwork
                        onOnlineChanged: if (online && root.open && root.step === root.stepNetwork) autoAdvance.restart()
                    }
                    Note { visible: !root.online; text: "You can also continue offline — the sign-in and the restore stay available later in Settings → Account." }
                }

                // ── 3 · updates ──
                // The installed system carries the sync database of its
                // install day; Arch mirrors drop old package versions within
                // days, so `pacman -S anything` on a stale database fails with
                // 404s. Komble refuses partial upgrades by design — so the ONE
                // safe move, a full upgrade, is offered here, before the app
                // restore can try to install anything.
                Column {
                    visible: root.step === root.stepUpdates
                    width: parent.width; spacing: Theme.spaceMd
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; ic: Theme.icRefresh }
                    Title { text: root.updState === "done" ? "Up to date" : root.updState === "current" ? "Your system is up to date" : "Bring the system up to date" }
                    Body {
                        text: root.updState === "checking" ? "Checking for updates…"
                            : root.updState === "current" ? "Nothing is waiting. Moving on."
                            : root.updState === "pending" ? root.updCount + (root.updCount === 1 ? " update is" : " updates are") + " waiting. A fresh install must be current before apps can be installed — the package list it was born with points at versions the mirrors have already replaced."
                            : root.updState === "installing" ? "Installing updates. This can take a few minutes; the desktop stays usable."
                            : root.updState === "done" ? "Done — some changes apply at your next login."
                            : root.updState === "failed" ? "The upgrade did not finish. You can retry now, or later from Komble → Updates."
                            : "Could not check for updates right now. Komble → Updates has them whenever you are ready."
                    }
                    Row {
                        visible: root.updBusy
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceS
                        Spinner { anchors.verticalCenter: parent.verticalCenter; size: Theme.iconMd }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.updState === "checking" ? "Checking…" : "Installing…"
                            color: Theme.textMuted
                            font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                        }
                    }
                    // the last lines of pacman, so a long upgrade is visibly alive
                    Rectangle {
                        visible: root.updTail.length > 0
                        width: parent.width; height: updLog.implicitHeight + 2 * Theme.spaceS
                        radius: Theme.radiusPrimary
                        color: root.updState === "failed" ? Theme.dangerSubtle : Theme.surfaceSunken
                        border.color: root.updState === "failed" ? Theme.danger : Theme.borderSubtle
                        border.width: Theme.borderWidth1
                        Text {
                            id: updLog
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: Theme.spaceS
                            anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                            text: root.updTail.join("\n")
                            color: root.updState === "failed" ? Theme.danger : Theme.textSecondary
                            font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeXs
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }

                // ── 4 · your account: Nextcloud ──
                Column {
                    visible: root.step === root.stepSignIn
                    width: parent.width; spacing: Theme.spaceMd
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.icon4xl; height: Theme.icon4xl
                        radius: Theme.radiusRounded
                        color: Theme.accentSubtle
                        Image {
                            anchors.centerIn: parent
                            source: Qt.resolvedUrl("assets/nextcloud.svg")
                            width: Theme.icon2xl; height: Theme.icon2xl
                            sourceSize.width: 2 * Theme.icon2xl; sourceSize.height: 2 * Theme.icon2xl
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    Title { text: Cloud.signedIn ? "Signed in" : "Your account: Nextcloud" }
                    Body {
                        visible: !Cloud.signedIn
                        text: "ewe keeps your machine in sync as one file, restores your apps through Komble, shows your calendar in Quick settings and keeps your files in ~/Nextcloud — all in YOUR Nextcloud: a server you run, or a hosted account (Murena, Disroot, Infomaniak…). Nothing about it is baked into ewe.\n\nSkip it and nothing changes; you can sign in later in Settings → Account."
                    }
                    // signed in: who, and what just got set up
                    Row {
                        visible: Cloud.signedIn
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceS + Theme.spaceXs
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.controlXl; height: Theme.controlXl
                            radius: Theme.radiusFull
                            color: Theme.surfaceHover
                            clip: true
                            Text {
                                anchors.centerIn: parent; visible: wAv.status !== Image.Ready
                                text: (Cloud.displayName || "?").charAt(0).toUpperCase()
                                color: Theme.textPrimary
                                font.family: Theme.type.h4.family; font.pixelSize: Theme.type.h4.size
                                font.weight: Theme.type.h4.weight
                            }
                            Image { id: wAv; anchors.fill: parent; source: Cloud.avatarPath !== "" ? "file://" + Cloud.avatarPath : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXxs
                            Text {
                                text: Cloud.displayName; color: Theme.textPrimary
                                font.family: Theme.type.bodyStrong.family
                                font.pixelSize: Theme.type.bodyStrong.size
                                font.weight: Theme.fontWeightSemibold
                            }
                            Text {
                                text: (Cloud.email !== "" ? Cloud.email + " · " : "") + Cloud.serverHost
                                color: Theme.textMuted
                                font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                            }
                        }
                    }
                    Note { visible: Cloud.signedIn; text: "Your files are at ~/Nextcloud (Files → sidebar)." }
                    // the account app (RFC-006): machines, folder sync, conflicts
                    Note { visible: Cloud.signedIn && Globals.syncAppInstalled; text: "Folders and your machines: ewe-sync (the tray icon)." }
                    Row {
                        visible: Cloud.signedIn && Globals.syncAppInstalled
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceMd
                        LinkBtn { label: "Open ewe-sync"; onGo: Globals.openSync() }
                    }
                    // the server address — remembered between attempts
                    Rectangle {
                        visible: !Cloud.signedIn && Cloud.busy !== "signin"
                        width: parent.width; height: Theme.controlXl
                        radius: Theme.radiusPrimary
                        color: Theme.surfaceSunken
                        border.width: Theme.fieldBorderWidth
                        border.color: srvField.activeFocus ? Theme.focusRing : Theme.borderStrong
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        TextInput {
                            id: srvField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                            verticalAlignment: TextInput.AlignVCenter
                            text: Cloud.lastServer
                            color: Theme.textPrimary
                            font.family: Theme.type.bodyLg.family; font.pixelSize: Theme.type.bodyLg.size
                            clip: true; selectByMouse: true
                            onAccepted: if (root.online && text.trim() !== "") Cloud.signIn(text)
                            Text {
                                visible: srvField.text === "" && !srvField.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "https://cloud.example.org"; color: Theme.textMuted; font: srvField.font
                            }
                        }
                    }
                    Text {
                        visible: !root.online && Cloud.busy !== "signin" && !Cloud.signedIn
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: "You are offline. Sign-in needs a connection: go back to connect, or skip for now."
                        color: Theme.warning
                        font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                    }
                    Note {
                        visible: root.online && !Cloud.signedIn && Cloud.keyringPromptExpected
                        text: Cloud.keyringState === "locked"
                            ? "Your keyring is locked: a small “Unlock keyring” prompt will appear during sign-in — answer it with your login password."
                            : "A small “Choose password for new keyring” prompt will appear during sign-in — use your login password so it unlocks by itself at every login."
                    }
                    Row {
                        visible: Cloud.busy === "signin"
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceS
                        Spinner { anchors.verticalCenter: parent.verticalCenter; size: Theme.iconMd }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Waiting for the browser…"
                            color: Theme.textMuted
                            font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                        }
                    }
                    Text {
                        visible: Cloud.error !== ""
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: Cloud.error; color: Theme.danger
                        font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                    }
                    // the link itself, for when the browser hand-off did not
                    // happen (no default browser, odd session)
                    Row {
                        visible: Cloud.loginUrl !== "" && !Cloud.signedIn
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceMd
                        LinkBtn { label: "Open the sign-in page"; onGo: Cloud.openLoginUrl() }
                        LinkBtn { label: "Copy the link"; onGo: Cloud.copyLoginUrl() }
                    }
                    // a keyring that rejects the login password can only be
                    // replaced: PAM makes a fresh one at the next login
                    Row {
                        visible: root.online && !Cloud.signedIn && Cloud.busy !== "signin"
                                 && (Cloud.keyringTrouble || Cloud.keyringResetDone)
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceMd
                        LinkBtn { visible: !Cloud.keyringResetDone; label: "Reset the keyring"; onGo: Cloud.resetKeyring() }
                        LinkBtn { visible: Cloud.keyringResetDone; label: "Log out now"; onGo: Cloud.logOut() }
                    }
                }

                // ── 5 · restore ──
                Column {
                    visible: root.step === root.stepRestore
                    width: parent.width; spacing: Theme.spaceMd
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; ic: Theme.icDownload }
                    Title { text: "Your desktop is in your account" }
                    Body {
                        text: "A backup from “" + (Cloud.cloudInfo ? Cloud.cloudInfo.device : "another machine") + "”"
                            + (Cloud.cloudInfo && Cloud.cloudInfo.updatedAt ? " (saved " + Qt.formatDateTime(new Date(Cloud.cloudInfo.updatedAt), "d MMMM, h:mm AP") + ")" : "")
                            + " is waiting. Restore it and your layout, theme, keybinds and network profiles come back to this machine; your apps line up in Komble, one click from reinstalled."
                    }
                    Row {
                        visible: root._restoring
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceS
                        Spinner { anchors.verticalCenter: parent.verticalCenter; size: Theme.iconMd }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter; text: "Restoring…"
                            color: Theme.textMuted
                            font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                        }
                    }
                    Text {
                        visible: Cloud.syncError !== "" && !root._restoring
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: Cloud.syncError; color: Theme.danger
                        font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                    }
                }

                // ── 6 · tour ──
                Column {
                    visible: root.step === root.stepTour
                    width: parent.width; spacing: Theme.spaceMd
                    Title { text: "The sixty-second tour" }
                    // what the restore left for Komble
                    Rectangle {
                        visible: Cloud.restoreApps > 0 || Cloud.restorePlugins > 0
                        width: parent.width; height: appsRow.implicitHeight + 2 * (Theme.spaceS + Theme.spaceXs)
                        radius: Theme.radiusPrimary
                        color: Theme.accentSubtle
                        Row {
                            id: appsRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.spaceS + Theme.spaceXs
                            spacing: Theme.spaceS + Theme.spaceXs
                            Text {
                                anchors.verticalCenter: parent.verticalCenter; text: Theme.icDownload
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg; color: Theme.accentText
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.iconLg - openKomble.width - 2 * parent.spacing
                                wrapMode: Text.Wrap
                                text: Cloud.restorePhrase() + " → For you and Plugins: repository apps install in one go, AUR apps go through the PKGBUILD review first, plugins are cloned from their git URLs. Never automatic."
                                color: Theme.textPrimary
                                font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                            }
                            Btn { id: openKomble; anchors.verticalCenter: parent.verticalCenter; label: "Open Komble"; onGo: Globals.openStore() }
                        }
                    }
                    // the explicit first backup — a never-synced machine never
                    // pushes on its own (see Cloud.autoPushAllowed)
                    Rectangle {
                        visible: Cloud.signedIn && Cloud.lastSync === ""
                        width: parent.width; height: bkRow.implicitHeight + 2 * (Theme.spaceS + Theme.spaceXs)
                        radius: Theme.radiusPrimary
                        color: Theme.surfaceSunken
                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                        Row {
                            id: bkRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.spaceS + Theme.spaceXs
                            spacing: Theme.spaceS + Theme.spaceXs
                            Text {
                                anchors.verticalCenter: parent.verticalCenter; text: Theme.icRefresh
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg; color: Theme.accentText
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.iconLg - bkBtn.width - 2 * parent.spacing
                                wrapMode: Text.Wrap
                                text: root._backingUp ? "Backing this machine up to your account…" : "This machine is not backed up yet. Nothing is uploaded until you say so."
                                color: Theme.textPrimary
                                font.family: Theme.type.label.family; font.pixelSize: Theme.fontSizeS
                            }
                            Btn { id: bkBtn; anchors.verticalCenter: parent.verticalCenter; label: root._backingUp ? "Backing up…" : "Back up now"; enabled: !root._backingUp; onGo: { root._backingUp = true; Cloud.backUpNow() } }
                        }
                    }
                    Column {
                        width: parent.width; spacing: Theme.spaceS + Theme.spaceXs
                        TourRow { ic: Theme.icKeyboard; head: "The Super key"; text: "Tap Super for the Overview of your windows and workspaces. Super+D searches apps and files; Super+Return opens a terminal." }
                        TourRow { ic: Theme.icApps; head: "The dock"; text: "Your pinned apps and open windows live at the bottom. Right-click any app to pin it; the first icon is the launcher." }
                        TourRow { ic: Theme.icCog; head: "Quick settings and Settings"; text: "Super+N (or the clock) opens Quick settings — Wi-Fi, sound, cast, calendar, notifications. Super+, opens Settings." }
                        TourRow { ic: Theme.icDownload; head: "Komble"; text: "One store for everything: the Arch repositories, the AUR and AppImages, with updates in one place — the download glyph in the bar tells you when." }
                    }
                }

            }

                // ── footer: the step dots and the buttons, under a divider ──
                Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                Item {
                    width: parent.width
                    height: Theme.controlLg + 2 * (Theme.spaceS + Theme.spaceXs)
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceMd
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXs
                        Repeater {
                            model: 6
                            delegate: Rectangle {
                                required property int index
                                width: index === root.step ? Theme.spaceMd : Theme.spaceXs
                                height: Theme.spaceXs
                                radius: Theme.radiusFull
                                color: index === root.step ? Theme.accent
                                     : index < root.step ? Theme.textSecondary : Theme.borderStrong
                                Behavior on width {
                                    NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durBase; easing.type: Theme.ease }
                                }
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceMd
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceS
                        // step-specific secondary
                        Btn { visible: root.step === root.stepNetwork && !root.online; label: "Continue offline"; onGo: root.next() }
                        Btn { visible: root.step === root.stepUpdates && (root.updState === "pending" || root.updState === "failed" || root.updState === "unknown"); label: "Later"; onGo: root.next() }
                        Btn { visible: root.step === root.stepSignIn && Cloud.busy !== "signin" && !Cloud.signedIn; label: "Skip for now"; onGo: root.next() }
                        Btn { visible: root.step === root.stepSignIn && !root.online && Cloud.busy !== "signin" && !Cloud.signedIn; label: "Back"; onGo: root.step = root.stepNetwork }
                        Btn { visible: root.step === root.stepSignIn && Cloud.busy === "signin"; label: "Cancel"; onGo: Cloud.cancelSignIn() }
                        Btn { visible: root.step === root.stepRestore && !root._restoring; label: "Start fresh"; onGo: root.next() }
                        // step-specific primary
                        Btn { visible: root.step === 0; primary: true; label: "Get started"; onGo: root.next() }
                        Btn { visible: root.step === root.stepNetwork; primary: true; enabled: root.online; label: root.online ? "Continue" : "Waiting for a connection…"; onGo: root.next() }
                        Btn { visible: root.step === root.stepUpdates && root.updState === "pending"; primary: true; label: "Install updates"; onGo: root.installUpdates() }
                        Btn { visible: root.step === root.stepUpdates && root.updState === "failed"; primary: true; label: "Retry"; onGo: root.installUpdates() }
                        Btn { visible: root.step === root.stepUpdates && root.updBusy; primary: true; enabled: false; label: root.updState === "checking" ? "Checking…" : "Installing…" }
                        Btn { visible: root.step === root.stepUpdates && (root.updState === "done" || root.updState === "current"); primary: true; label: "Continue"; onGo: root.next() }
                        Btn { visible: root.step === root.stepSignIn && Cloud.busy !== "signin" && !Cloud.signedIn; primary: true; enabled: root.online && srvField.text.trim() !== ""; label: "Sign in"; onGo: Cloud.signIn(srvField.text) }
                        Btn { visible: root.step === root.stepSignIn && Cloud.signedIn; primary: true; label: "Continue"; onGo: root.next() }
                        Btn { visible: root.step === root.stepRestore && !root._restoring; primary: true; label: "Restore my desktop"
                              onGo: { root._restoring = true; Cloud.pendingRestore = { updatedAt: Cloud.cloudInfo.updatedAt, device: Cloud.cloudInfo.device }; Cloud.applyRestore() } }
                        Btn { visible: root.step === root.stepTour; primary: true; label: "Finish"; onGo: root.finish() }
                    }
                }
            }
        }
    }
}
