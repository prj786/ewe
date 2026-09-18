import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// BtPairing — the Bluetooth pairing dialog (design system: Bluetooth
// pairing, on the Dialog). It renders BtAgent.request, the one question
// bluez is asking:
//
//   confirm    "Pair with X?"                  the code    Cancel · Pair
//   authorize  "Pair with X?"                              Cancel · Pair
//   service    "Allow X to connect?"           the service Deny · Allow
//   pin        "Enter the PIN for X"           PIN field   Cancel · Pair
//   passkey    "Enter the code shown on X"     6 digits    Cancel · Pair
//   display    "Type this code on X"    the code, typed so far, Cancel only
//
//   dialog      panelSm + spaceMd + spaceXxs (378) wide on surfaceRaised,
//               radiusRounded, shadowFloat, spaceMd of padding, over `scrim`
//   head        an icon2xl accentSubtle circle with an accentText bluetooth
//               glyph and the h3 title, which names the device
//   device box  NEW (the card): surfaceSunken with the device's own glyph,
//               its name in semibold and its address in Geist Mono
//   code box    control2xl + spaceS tall, surfaceSunken inside a borderStrong
//               outline, mono display (28) semibold with spaceXs of tracking;
//               on `display` the digits already typed are accentText and the
//               rest textDisabled
//   hint        the label style in textSecondary, centred
//   footer      Cancel / Deny (ghost) and Pair / Allow (primary), right —
//               `display` has nothing to accept, so Cancel takes the width
//
// Enter accepts, Esc denies. NEW: a passkey that is not 1–6 digits says so
// under the field instead of being ignored.
Scope {
    id: root
    readonly property var req: BtAgent.request
    readonly property string kind: req ? String(req.kind) : ""
    readonly property string devName: req && req.device ? (req.device.name || req.device.address) : ""
    readonly property string devAddress: req && req.device ? String(req.device.address || "") : ""
    readonly property bool needsInput: kind === "pin" || kind === "passkey"
    readonly property bool showsCode: kind === "confirm" || kind === "display"
    readonly property string code: req && req.passkey ? String(req.passkey) : ""
    readonly property int typed: (kind === "display" && req && req.entered) ? req.entered : 0

    function title() {
        switch (kind) {
        case "confirm":   return "Pair with " + devName + "?"
        case "authorize": return "Pair with " + devName + "?"
        case "service":   return "Allow " + devName + " to connect?"
        case "pin":       return "Enter the PIN for " + devName
        case "passkey":   return "Enter the code shown on " + devName
        case "display":   return "Type this code on " + devName
        }
        return "Bluetooth"
    }
    function hint() {
        switch (kind) {
        case "confirm":   return "Check that the same code shows on the device."
        case "authorize": return "This device is asking to pair with this computer."
        case "service":   return devName + " wants to use " + (req.service || "a service") + "."
        case "pin":       return "Often 0000 or 1234. Check the device's manual."
        case "passkey":   return "The six-digit code is shown on the device."
        case "display":
            return root.typed > 0
                ? root.typed + " of 6 typed. Type the code on the keyboard, then press Enter."
                : "Type the code on the keyboard, then press Enter."
        }
        return ""
    }
    function okLabel() { return kind === "service" ? "Allow" : "Pair" }
    function cancelLabel() { return kind === "service" ? "Deny" : "Cancel" }
    // the card's passkey rule: say what is wrong, do not swallow the key
    readonly property string inputError: (kind === "passkey" && inField.text.trim() !== ""
                                          && !/^[0-9]{1,6}$/.test(inField.text.trim()))
                                         ? "Use up to 6 digits" : ""
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

        Rectangle { anchors.fill: parent; color: Theme.scrim }
        MouseArea { anchors.fill: parent }    // swallow — only the buttons or Esc dismiss

        Connections {
            target: BtAgent
            function onRequestChanged() { if (BtAgent.request) { inField.text = ""; keys.forceActiveFocus(); if (root.needsInput) inField.forceActiveFocus() } }
        }

        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: Theme.panelSm + Theme.spaceMd + Theme.spaceXxs
            height: col.implicitHeight + 2 * Theme.spaceMd
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1
            layer.enabled: true
            layer.effect: Elevation {}
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
                anchors.margins: Theme.spaceMd
                spacing: Theme.spaceMd

                // ── head: the bluetooth mark and the title ────────────────
                Row {
                    width: parent.width
                    spacing: Theme.spaceS + Theme.spaceXs
                    Rectangle {
                        width: Theme.icon2xl; height: Theme.icon2xl
                        radius: Theme.radiusFull
                        color: Theme.accentSubtle
                        antialiasing: true
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icBluetooth
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: Theme.accentText
                        }
                    }
                    Text {
                        width: parent.width - Theme.icon2xl - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.title()
                        color: Theme.textPrimary
                        font.family: Theme.type.h3.family
                        font.pixelSize: Theme.type.h3.size
                        font.weight: Theme.type.h3.weight
                        font.letterSpacing: Theme.type.h3.letterSpacing
                        wrapMode: Text.Wrap
                    }
                }

                // ── the device box (new): what is asking ──────────────────
                Rectangle {
                    width: parent.width
                    height: Theme.controlLg + Theme.spaceS
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    Row {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceS
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: BtAgent.glyph(root.req && root.req.device ? root.req.device.icon : "", false)
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: Theme.textSecondary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.devName
                            color: Theme.textPrimary
                            font.family: Theme.type.label.family
                            font.pixelSize: Theme.fontSizeS
                            font.weight: Theme.fontWeightSemibold
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.devAddress !== ""
                            text: "· " + root.devAddress
                            color: Theme.textSecondary
                            font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeS
                        }
                    }
                }

                // ── the code — big, spaced digits; on `display` the ones
                //    already typed are accentText and the rest are waiting ──
                Rectangle {
                    visible: root.showsCode
                    width: parent.width
                    height: Theme.control2xl + Theme.spaceS
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    border.color: Theme.borderStrong; border.width: Theme.borderWidth1
                    Row {
                        anchors.centerIn: parent
                        spacing: 0
                        Repeater {
                            model: root.code.length
                            delegate: Text {
                                required property int index
                                text: root.code.charAt(index)
                                color: root.kind !== "display" ? Theme.textPrimary
                                     : index < root.typed ? Theme.accentText : Theme.textDisabled
                                font.family: Theme.type.mono.family
                                font.pixelSize: Theme.fontSize3xl
                                font.weight: Theme.fontWeightSemibold
                                font.letterSpacing: Theme.spaceXs
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }

                // ── PIN / passkey entry, with its label and error ─────────
                Column {
                    visible: root.needsInput
                    width: parent.width
                    spacing: Theme.spaceXs
                    Text {
                        text: root.kind === "passkey" ? "Code" : "PIN"
                        color: Theme.textPrimary
                        font.family: Theme.type.label.family
                        font.pixelSize: Theme.type.label.size
                        font.weight: Theme.type.label.weight
                    }
                    Rectangle {
                        width: parent.width
                        height: Theme.controlLg
                        radius: Theme.radiusPrimary
                        color: Theme.surfaceSunken
                        border.width: Theme.fieldBorderWidth
                        border.color: root.inputError !== "" ? Theme.danger
                                    : inField.activeFocus ? Theme.focusRing : Theme.borderStrong
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        TextInput {
                            id: inField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textPrimary
                            font.family: Theme.type.mono.family
                            font.pixelSize: Theme.type.body.size
                            inputMethodHints: root.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                            maximumLength: root.kind === "passkey" ? 6 : 16
                            onAccepted: root.accept()
                            Keys.onEscapePressed: root.reject()
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: inField.text.length === 0
                                text: root.kind === "passkey" ? "6 digits" : "PIN"
                                color: Theme.textMuted; font: inField.font
                            }
                        }
                    }
                    Row {
                        visible: root.inputError !== ""
                        spacing: Theme.spaceXs
                        Text {
                            text: Theme.icWarning
                            font.family: Theme.fontIcons; font.pixelSize: Theme.lineHeightXs
                            color: Theme.danger
                        }
                        Text {
                            text: root.inputError
                            color: Theme.danger
                            font.family: Theme.type.caption.family
                            font.pixelSize: Theme.type.caption.size
                        }
                    }
                }

                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: root.hint()
                    visible: text.length > 0
                    color: Theme.textSecondary
                    font.family: Theme.type.label.family
                    font.pixelSize: Theme.fontSizeS
                    wrapMode: Text.Wrap
                }

                // ── footer ───────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: Theme.controlMd
                    Rectangle {
                        id: cancelBtn
                        anchors.right: root.kind === "display" ? parent.right : okBtn.left
                        anchors.rightMargin: root.kind === "display" ? 0 : Theme.spaceS
                        anchors.left: root.kind === "display" ? parent.left : undefined
                        height: Theme.controlMd
                        width: root.kind === "display" ? parent.width
                                                       : cancelTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                        radius: Theme.radiusPrimary
                        color: cancelMa.pressed ? Theme.surfacePressed
                             : cancelMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent; text: root.cancelLabel()
                            color: Theme.textPrimary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            font.weight: Theme.fontWeightMedium
                        }
                        MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.reject() }
                    }
                    Rectangle {
                        id: okBtn
                        visible: root.kind !== "display"
                        anchors.right: parent.right
                        height: Theme.controlMd
                        width: okTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                        radius: Theme.radiusPrimary
                        color: okMa.pressed ? Theme.accentPressed
                             : okMa.containsMouse ? Theme.accentHover : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            id: okTxt
                            anchors.centerIn: parent; text: root.okLabel()
                            color: Theme.onAccent
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            font.weight: Theme.fontWeightMedium
                        }
                        MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.accept() }
                    }
                }
            }
        }
    }
}
