import QtQuick
import Quickshell
import Quickshell.Wayland

// BtPairing — the Bluetooth pairing dialog. Renders BtAgent.request (the one
// question bluez is asking) in the same modal shape as Auth (polkit):
//   confirm    "Pair with X?"  big 6-digit code   Cancel / Pair
//   authorize  "X wants to pair"                  Cancel / Pair
//   service    "X wants to use <profile>"         Deny / Allow
//   pin        text field                         Cancel / Pair
//   passkey    6-digit field                      Cancel / Pair
//   display    big code to TYPE on the device, keys-typed progress, Cancel
Scope {
    id: root
    readonly property var req: BtAgent.request
    readonly property string kind: req ? String(req.kind) : ""
    readonly property string devName: req && req.device ? (req.device.name || req.device.address) : ""
    readonly property bool needsInput: kind === "pin" || kind === "passkey"
    readonly property bool showsCode: kind === "confirm" || kind === "display"

    function title() {
        switch (kind) {
        case "confirm":   return "Pair with " + devName + "?"
        case "authorize": return devName + " wants to pair"
        case "service":   return devName + " wants to connect"
        case "pin":       return "Enter the PIN for " + devName
        case "passkey":   return "Enter the passkey for " + devName
        case "display":   return "Type this on " + devName
        }
        return "Bluetooth"
    }
    function hint() {
        switch (kind) {
        case "confirm":   return "Make sure the same code is shown on the device, then pair."
        case "authorize": return "Allow this device to pair with this computer?"
        case "service":   return "It wants to use " + (req.service || "a service") + ". Allow it?"
        case "pin":       return "The PIN is printed on the device or shown on its screen (often 0000 or 1234)."
        case "passkey":   return "The six-digit passkey is shown on the device."
        case "display":
            var n = req && req.entered ? req.entered : 0
            return n > 0 ? (n + " of 6 typed — finish with Enter") : "Type the code on its keyboard and press Enter."
        }
        return ""
    }
    function okLabel() { return kind === "service" ? "Allow" : "Pair" }
    function cancelLabel() { return kind === "service" ? "Deny" : "Cancel" }
    function accept() {
        if (needsInput) {
            var v = inField.text.trim()
            if (v === "") return
            if (kind === "passkey" && !/^[0-9]{1,6}$/.test(v)) return
            BtAgent.reply(true, v); inField.text = ""
        } else BtAgent.reply(true, "")
    }
    function reject() { BtAgent.reply(false, ""); inField.text = "" }

    PanelWindow {
        id: win
        visible: root.req !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:btpairing"
        WlrLayershell.layer: WlrLayer.Overlay
        // typing a PIN needs the keyboard; a yes/no only needs Esc/Enter
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle { anchors.fill: parent; color: Theme.shadow }
        MouseArea { anchors.fill: parent }    // swallow — only the buttons or Esc dismiss

        Connections {
            target: BtAgent
            function onRequestChanged() { if (BtAgent.request) { inField.text = ""; keys.forceActiveFocus(); if (root.needsInput) inField.forceActiveFocus() } }
        }

        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: 400
            height: col.implicitHeight + 40
            radius: Theme.radius
            color: Theme.bg1
            border.color: Theme.stroke2
            border.width: Theme.borderThin
            MouseArea { anchors.fill: parent }
            // Esc / Enter for the yes-no kinds (the field handles its own)
            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.reject()
                Keys.onReturnPressed: root.accept()
                Keys.onEnterPressed: root.accept()
            }

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 20
                spacing: 13

                // device glyph + title
                Column {
                    width: parent.width; spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: BtAgent.glyph(root.req && root.req.device ? root.req.device.icon : "", false)
                        font.family: Theme.fontIcons; font.pixelSize: 28; color: Theme.accent
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: root.title()
                        color: Theme.fg1; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }
                }

                // the code — big, spaced digits, monospace so 1 and 7 read apart
                Rectangle {
                    visible: root.showsCode
                    width: parent.width; height: 56; radius: Theme.r(9)
                    color: Theme.bg3; border.color: Theme.stroke1; border.width: Theme.borderThin
                    Text {
                        anchors.centerIn: parent
                        text: root.req && root.req.passkey ? String(root.req.passkey) : ""
                        color: Theme.fg1; font.family: Theme.fontMono; font.pixelSize: 30; font.weight: Font.Bold
                        font.letterSpacing: 6
                    }
                }

                // PIN / passkey entry
                Rectangle {
                    visible: root.needsInput
                    width: parent.width; height: 38; radius: Theme.r(9)
                    color: Theme.bg3
                    border.color: inField.activeFocus ? Theme.accent : Theme.stroke1
                    border.width: Theme.borderThin
                    TextInput {
                        id: inField
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg1; font.family: Theme.fontMono; font.pixelSize: Theme.fsBody
                        inputMethodHints: root.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                        maximumLength: root.kind === "passkey" ? 6 : 16
                        onAccepted: root.accept()
                        Keys.onEscapePressed: root.reject()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: inField.text.length === 0
                            text: root.kind === "passkey" ? "6 digits" : "PIN"
                            color: Theme.fg3; font: inField.font
                        }
                    }
                }

                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: root.hint()
                    visible: text.length > 0
                    color: Theme.fg2; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap
                }

                Row {
                    width: parent.width
                    spacing: 10
                    Rectangle {
                        width: root.kind === "display" ? parent.width : (parent.width - 10) / 2; height: 36; radius: Theme.r(9)
                        color: cancelMa.containsMouse ? Theme.cardHover : Theme.card
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Text { anchors.centerIn: parent; text: root.cancelLabel(); color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsBody }
                        MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.reject() }
                    }
                    Rectangle {
                        visible: root.kind !== "display"
                        width: (parent.width - 10) / 2; height: 36; radius: Theme.r(9)
                        color: okMa.containsMouse ? Theme.brandBgHover : Theme.accentFill
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Text { anchors.centerIn: parent; text: root.okLabel(); color: Theme.accentOn; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                        MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.accept() }
                    }
                }
            }
        }
    }
}
