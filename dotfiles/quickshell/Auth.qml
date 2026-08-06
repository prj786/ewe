import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

// Auth — a custom polkit authentication agent. Whenever something needs elevated
// privileges (a "sudo"/admin password), this dialog appears instead of
// the default lxqt/gnome one. Enter the password for your (sudo) user.
Scope {
    id: root

    PolkitAgent { id: agent }

    PanelWindow {
        id: win
        visible: agent.isActive && agent.flow !== null
        color: "transparent"
        // a modal: the dim backdrop covers the WHOLE screen, dock and bar
        // included — reserved strips would leave undimmed bands around it
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:auth"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        // dim backdrop — swallows clicks; only the Cancel button (or Esc) dismisses
        Rectangle { anchors.fill: parent; color: Theme.shadow }
        MouseArea { anchors.fill: parent }

        Connections {
            target: agent
            function onIsActiveChanged() { if (agent.isActive) pwField.forceActiveFocus() }
            function onFlowChanged() { if (agent.flow) { pwField.text = ""; pwField.forceActiveFocus() } }
        }

        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: 380
            height: col.implicitHeight + 40
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.stroke
            border.width: 1
            MouseArea { anchors.fill: parent }   // swallow clicks

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 20
                spacing: 13

                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "Authentication Required"
                    color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: agent.flow ? agent.flow.message : ""
                    visible: text.length > 0
                    color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap
                }

                // password field
                Rectangle {
                    width: parent.width; height: 38; radius: 9
                    color: Theme.bg
                    border.color: pwField.activeFocus ? Theme.accent : Theme.stroke
                    border.width: 1
                    TextInput {
                        id: pwField
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody
                        echoMode: (agent.flow && agent.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                        enabled: agent.flow && agent.flow.isResponseRequired
                        onAccepted: if (agent.flow) { agent.flow.submit(text); text = "" }
                        Keys.onEscapePressed: if (agent.flow) agent.flow.cancelAuthenticationRequest()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pwField.text.length === 0
                            text: agent.flow && agent.flow.inputPrompt ? agent.flow.inputPrompt : "Password"
                            color: Theme.fgDim; font: pwField.font
                        }
                    }
                }

                // error / supplementary message
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: agent.flow ? (agent.flow.supplementaryMessage !== "" ? agent.flow.supplementaryMessage : (agent.flow.failed ? "Authentication failed — try again" : "")) : ""
                    visible: text.length > 0
                    color: (agent.flow && (agent.flow.supplementaryIsError || agent.flow.failed)) ? Theme.danger : Theme.fgDim
                    font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap
                }

                // buttons — the pair spans exactly the password field's width,
                // so their outer edges line up with the input above
                Row {
                    width: parent.width
                    spacing: 10
                    Rectangle {
                        width: (parent.width - 10) / 2; height: 36; radius: 9
                        color: cancelMa.containsMouse ? Theme.hover : Theme.elevated
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody }
                        MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (agent.flow) agent.flow.cancelAuthenticationRequest() }
                    }
                    Rectangle {
                        width: (parent.width - 10) / 2; height: 36; radius: 9
                        color: okMa.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Text { anchors.centerIn: parent; text: "Authenticate"; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                        MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (agent.flow) { agent.flow.submit(pwField.text); pwField.text = "" } }
                    }
                }
            }
        }
    }
}
