import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs

// ewe.slack — the Connect window: offered once on the first start without a
// token, and from the widget's cog. Opens Slack's "create app" page with the
// manifest filled in, takes the User OAuth Token in a password field and
// hands it to SlackInbox.connect() (checked with Slack, then the keyring).
// Connected, it says as whom and offers Disconnect. A panel and not part of
// the widget: desktop widgets never take the keyboard.
Scope {
    id: root

    PanelWindow {
        id: win
        visible: SlackInbox.setupOpen || win.held
        screen: {
            var s = Quickshell.screens, fm = Hyprland.focusedMonitor
            if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
            return s.length > 0 ? s[0] : null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:ewe.slack"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: SlackInbox.setupOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: { win.held = false; input.text = "" } }
        Connections {
            target: SlackInbox
            function onSetupOpenChanged() {
                if (SlackInbox.setupOpen) { closeTimer.stop(); win.held = true; input.text = ""; input.forceActiveFocus() }
                else closeTimer.restart()
            }
        }

        MouseArea { anchors.fill: parent; onClicked: SlackInbox.setupOpen = false }

        Rectangle {
            id: panel
            width: Theme.grow(Theme.panelMd)
            height: col.implicitHeight + 2 * Theme.spaceMd
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.24)
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            opacity: SlackInbox.setupOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: SlackInbox.setupOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
            transform: Translate {
                y: (SlackInbox.setupOpen || Theme.reduceMotion) ? 0 : Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
            layer.enabled: true
            layer.effect: Elevation {}
            MouseArea { anchors.fill: parent }

            Keys.onEscapePressed: SlackInbox.setupOpen = false

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spaceMd
                spacing: Theme.spaceS

                Item {
                    width: parent.width; height: Theme.controlLg
                    Row {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceS
                        Glyph { anchors.verticalCenter: parent.verticalCenter; text: Theme.icMessage }
                        TextStrong { anchors.verticalCenter: parent.verticalCenter; text: SlackInbox.connected ? "Slack" : "Connect Slack" }
                    }
                    QsIconButton {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        ic: Theme.icClose; onGo: SlackInbox.setupOpen = false
                    }
                }

                // ── connected: who, and the way out ──
                Column {
                    visible: SlackInbox.connected
                    width: parent.width
                    spacing: Theme.spaceS
                    TextBody {
                        width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone
                        text: "Connected as " + (SlackInbox.userName || "you") + (SlackInbox.teamName ? " in " + SlackInbox.teamName : "") + "."
                    }
                    QsNote { text: "The token is kept in your keyring. Disconnect removes it from there; the Slack app itself stays in your workspace until you delete it at api.slack.com/apps." }
                    Row {
                        anchors.right: parent.right
                        spacing: Theme.spaceS
                        QsButton { label: "Disconnect"; onGo: { SlackInbox.disconnect(); input.forceActiveFocus() } }
                        QsButton { label: "Done"; variant: "primary"; onGo: SlackInbox.setupOpen = false }
                    }
                }

                // ── not connected: make the app, paste its token ──
                Column {
                    visible: !SlackInbox.connected
                    width: parent.width
                    spacing: Theme.spaceS
                    TextBody {
                        width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone
                        text: "1. Create a Slack app for your workspace. Slack opens with everything filled in: pick the workspace, Create, then Install to Workspace."
                    }
                    QsButton { label: "Create the Slack app"; ic: Theme.icWeb; onGo: SlackInbox.createApp() }
                    TextBody {
                        width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone
                        text: "2. On the app's OAuth & Permissions page, copy the User OAuth Token and paste it here."
                    }
                    QsField {
                        focused: input.activeFocus
                        error: SlackInbox.connectError !== ""
                        QsFieldInput {
                            id: input
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            placeholder: "xoxp-…"
                            echoMode: TextInput.Password
                            onAccepted: if (text.trim() !== "") SlackInbox.connect(text)
                        }
                    }
                    QsNote { visible: SlackInbox.connectError !== ""; tone: "danger"; text: SlackInbox.connectError }
                    QsNote { text: "Slack checks the token first; then it is kept in your keyring, never in ewe.conf." }
                    Row {
                        anchors.right: parent.right
                        spacing: Theme.spaceS
                        QsButton { label: "Cancel"; onGo: SlackInbox.setupOpen = false }
                        QsButton {
                            label: "Connect"; variant: "primary"
                            busy: SlackInbox.connecting
                            disabled: input.text.trim() === "" || SlackInbox.connecting
                            onGo: SlackInbox.connect(input.text)
                        }
                    }
                }
            }
        }
    }
}
