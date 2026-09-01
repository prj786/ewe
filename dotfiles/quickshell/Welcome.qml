import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Welcome — what a stranger sees in their first minute (ROADMAP 0.7).
// Shown ONCE on a fresh install (stamp: ~/.local/state/ewe/welcomed), never
// on the live ISO (EWE_LIVE — the installer is the point there). Four steps:
//   1 welcome · 2 one sign-in (Google) · 3 restore offer (only when the
//   account holds a backup from another machine) · 4 the 60-second tour.
// Re-open any time:  qs ipc call welcome toggle   (reset: … welcome reset)
Scope {
    id: root

    property bool open: false
    property int step: 0
    readonly property string stamp: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ewe/welcomed"

    // a restore is worth offering when the account has a backup and THIS
    // machine has never synced — the same rule Google._maybeOfferRestore uses
    readonly property bool restoreWorthIt: Google.signedIn && Google.cloudInfo !== null && Google.lastSync === ""

    function finish() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && : > "$1"', "sh", root.stamp])
        root.open = false
    }
    function next() {
        if (root.step === 1 && !root.restoreWorthIt) { root.step = 3; return }   // nothing to restore → tour
        if (root.step >= 3) { root.finish(); return }
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

    // sign-in landed while the account step is up → move on by itself
    Connections {
        target: Google
        function onSignedInChanged() {
            if (root.open && root.step === 1 && Google.signedIn) Google.checkCloud(function (ok) { root.next() })
        }
        function onSyncStateChanged() {
            if (root.open && root.step === 2 && root._restoring && Google.syncState !== "syncing") { root._restoring = false; root.step = 3 }
        }
    }
    property bool _restoring: false

    PanelWindow {
        id: win
        visible: root.open || win.held
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:welcome"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections { target: root; function onOpenChanged() { if (root.open) { closeTimer.stop(); win.held = true; keys.forceActiveFocus() } else closeTimer.restart() } }

        // dimmed desktop behind the card
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: root.open ? 0.62 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.ease } }
            MouseArea { anchors.fill: parent }   // swallow — the card is the only way out
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.finish()
            Keys.onReturnPressed: root.next()
            Keys.onEnterPressed: root.next()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 600
            height: body.implicitHeight + 40
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            layer.enabled: true
            layer.effect: Elevation {}
            Sheen { radius: parent.radius }
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.ease } }
            Behavior on scale { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.ease } }
            Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            MouseArea { anchors.fill: parent }

            // ── shared bits ──
            component Title: Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: 26; font.weight: Font.Bold
            }
            component Body: Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; lineHeight: 1.25
            }
            component Btn: Rectangle {
                id: b
                property string label: ""
                property bool primary: false
                property bool enabled: true
                signal go()
                width: bt.implicitWidth + 36; height: 40; radius: 12
                opacity: enabled ? 1 : 0.45
                color: primary ? (bMa.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent)
                               : (bMa.containsMouse ? Theme.hover : Theme.elevated)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text { id: bt; anchors.centerIn: parent; text: b.label; color: b.primary ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; cursorShape: Qt.PointingHandCursor; onClicked: b.go() }
            }
            component Glyph: Rectangle {
                property string ic: ""
                width: 64; height: 64; radius: 20
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                Text { anchors.centerIn: parent; text: parent.ic; font.family: Theme.fontIcons; font.pixelSize: 30; color: Theme.accent }
            }
            component TourRow: Row {
                property string ic: ""
                property string head: ""
                property string text: ""
                width: parent.width; spacing: 14
                Rectangle {
                    width: 44; height: 44; radius: 14
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                    Text { anchors.centerIn: parent; text: parent.parent.ic; font.family: Theme.fontIcons; font.pixelSize: 20; color: Theme.accent }
                }
                Column {
                    width: parent.width - 58; spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: parent.parent.head; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: parent.parent.text; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                }
            }

            Column {
                id: body
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 20; anchors.leftMargin: 36; anchors.rightMargin: 36
                spacing: 18

                Item { width: 1; height: 8 }

                // ── 1 · welcome ──
                Column {
                    visible: root.step === 0
                    width: parent.width; spacing: 16
                    Image { anchors.horizontalCenter: parent.horizontalCenter; source: Qt.resolvedUrl("assets/logo.png"); width: 104; height: 104; sourceSize.width: 208; sourceSize.height: 208; fillMode: Image.PreserveAspectFit; mipmap: true }
                    Title { text: "Welcome to ewe" }
                    Body { text: "A clean, dark desktop that stays out of your way.\nThree short steps and it is yours." }
                }

                // ── 2 · one sign-in ──
                Column {
                    visible: root.step === 1
                    width: parent.width; spacing: 16
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; ic: Theme.icUser }
                    Title { text: "One sign-in for the whole desktop" }
                    Body { text: "Sign in with Google once and ewe lights up around it: calendar and mail in the Control Center, your machine kept in sync as one file, your apps restorable through Komble, and your Drive as a folder in Files.\n\nSkip it and nothing Google appears anywhere — you can sign in later in Settings → User." }
                    Text {
                        visible: Google.probed && !Google.configured
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: "Sign-in is unavailable on this build (no Google client shipped)."
                        color: Theme.warning; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                    }
                    Row {
                        visible: Google.busy === "signin"
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                        Spinner { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Waiting for the browser…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                    }
                    Text {
                        visible: Google.error !== ""
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: Google.error; color: Theme.danger; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                    }
                }

                // ── 3 · restore ──
                Column {
                    visible: root.step === 2
                    width: parent.width; spacing: 16
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; ic: Theme.icDownload }
                    Title { text: "Your desktop is in your Drive" }
                    Body {
                        text: "A backup from “" + (Google.cloudInfo ? Google.cloudInfo.device : "another machine") + "”"
                            + (Google.cloudInfo && Google.cloudInfo.updatedAt ? " (updated " + Qt.formatDateTime(new Date(Google.cloudInfo.updatedAt), "d MMMM, h:mm AP") + ")" : "")
                            + " is waiting. Restore it and your layout, theme, keybinds, network profiles and apps come back to this machine."
                    }
                    Row {
                        visible: root._restoring
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                        Spinner { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Restoring…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                    }
                }

                // ── 4 · tour ──
                Column {
                    visible: root.step === 3
                    width: parent.width; spacing: 16
                    Title { text: "The sixty-second tour" }
                    Column {
                        width: parent.width; spacing: 14
                        TourRow { ic: Theme.icKeyboard; head: "The Super key"; text: "Tap Super for the overview of your windows and workspaces. Super + D searches apps and files; Super + Return opens a terminal." }
                        TourRow { ic: Theme.icApps; head: "The dock"; text: "Your pinned apps and open windows live at the bottom. Right-click any app to pin it; the first icon is the launcher." }
                        TourRow { ic: Theme.icCog; head: "Control Center and Settings"; text: "Super + N (or the clock) opens the Control Center — Wi-Fi, sound, cast, calendar, notifications. Super + , opens Settings." }
                        TourRow { ic: Theme.icDownload; head: "Komble"; text: "One store for everything: the Arch repositories, the AUR and AppImages, with updates in one place — the download glyph in the top bar tells you when." }
                    }
                }

                // ── footer: dots + buttons ──
                Item {
                    width: parent.width; height: 44
                    Row {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                required property int index
                                width: index === root.step ? 18 : 6; height: 6; radius: 3
                                color: index === root.step ? Theme.accent : Theme.hover
                                Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        // step-specific secondary
                        Btn { visible: root.step === 1 && Google.busy !== "signin"; label: "Skip for now"; onGo: root.next() }
                        Btn { visible: root.step === 1 && Google.busy === "signin"; label: "Cancel"; onGo: Google.cancelSignIn() }
                        Btn { visible: root.step === 2 && !root._restoring; label: "Start fresh"; onGo: root.next() }
                        // step-specific primary
                        Btn { visible: root.step === 0; primary: true; label: "Get started"; onGo: root.next() }
                        Btn { visible: root.step === 1 && Google.busy !== "signin"; primary: true; enabled: Google.configured; label: "Sign in with Google"; onGo: Google.signIn() }
                        Btn { visible: root.step === 2 && !root._restoring; primary: true; label: "Restore my desktop"
                              onGo: { root._restoring = true; Google.pendingRestore = { updatedAt: Google.cloudInfo.updatedAt, device: Google.cloudInfo.device }; Google.applyRestore() } }
                        Btn { visible: root.step === 3; primary: true; label: "Finish"; onGo: root.finish() }
                    }
                }
            }
        }
    }
}
