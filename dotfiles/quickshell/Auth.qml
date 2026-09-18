import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

// Auth — the polkit authentication agent (design system: Authentication
// prompt, on the Dialog). Whenever something needs administrator rights this
// asks instead of the lxqt/gnome prompt.
//
//   placement  a small Dialog centred on the focused screen over `scrim`; it
//              takes all keyboard input until answered, and clicking the
//              scrim does nothing, so no work is lost by accident
//   dialog     panelSm + spaceMd + spaceXxs (378) wide, surfaceRaised with a
//              borderWidth1 borderSubtle outline, the radiusRounded corner,
//              shadowFloat, spaceMd of padding and spaceMd between sections
//   head       an icon2xl accentSubtle circle with an accentText shield-check,
//              the h3 title "Authentication required" and a body line saying
//              why
//   requester  NEW (the card): a surfaceSunken box naming what is being asked
//              for, with the polkit action id in Geist Mono
//   field      labelled "Password for <user>", with a lock glyph, focused on
//              open; it shows the text only when polkit asks for a visible
//              answer
//   footer     Cancel (ghost) and Authenticate (primary), right-aligned
//
//   checking       the field goes quiet with a Spinner, the helper reads
//                  "Checking…" and Authenticate waits
//   wrong password a danger border, the field cleared, and
//                  "Wrong password. Try again." below it
//
// Enter submits, Esc cancels.
Scope {
    id: root

    // The agent registers with polkitd when it is created. That fails with
    // "An authentication agent already exists for the given subject" while a
    // previous shell instance still holds the registration (a shell restart
    // mid-update — metal, 2026-09-02); once that instance is gone NOTHING
    // answers pkexec and Komble / Welcome fail with "polkit refused". So the
    // agent lives in a Loader and is re-created until polkitd accepts it, and
    // again whenever the registration is lost later (polkitd restart).
    property var agent: agentLoader.item
    readonly property var flow: agent ? agent.flow : null
    Loader { id: agentLoader; active: true; sourceComponent: PolkitAgent {} }
    Timer {
        interval: 5000; repeat: true; running: true
        property int tries: 0
        onTriggered: {
            if (agentLoader.item && agentLoader.item.isRegistered) { tries = 0; return }
            tries += 1
            if (tries === 3 || tries % 60 === 0) Log.warn("auth", "polkit agent not registered yet — re-creating (try " + tries + ")")
            agentLoader.active = false
            agentLoader.active = true
        }
    }

    // polkit publishes no "checking" flag: the answer is in flight from the
    // moment it is submitted until the flow answers or asks again
    property bool checking: false
    readonly property string user: Quickshell.env("USER") || "this account"
    readonly property bool wrong: root.flow !== null && root.flow.failed
    function submit(text) {
        if (!root.flow) return
        root.checking = true
        root.flow.submit(text)
    }

    PanelWindow {
        id: win
        visible: (root.agent && root.agent.isActive) && root.flow !== null
        color: "transparent"
        // a modal: the scrim covers the WHOLE screen, dock and bar included —
        // reserved strips would leave undimmed bands around it
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:auth"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        // the scrim — it swallows clicks; only Cancel (or Esc) dismisses
        Rectangle { anchors.fill: parent; color: Theme.scrim }
        MouseArea { anchors.fill: parent }

        Connections {
            target: root.agent
            function onIsActiveChanged() { if (root.agent && root.agent.isActive) pwField.forceActiveFocus() }
            function onFlowChanged() { if (root.flow) { root.checking = false; pwField.text = ""; pwField.forceActiveFocus() } }
        }
        Connections {
            target: root.flow
            // the flow talking back is the end of the wait, either way
            function onFailedChanged() { root.checking = false; if (root.flow && root.flow.failed) pwField.text = "" }
            function onSupplementaryMessageChanged() { root.checking = false }
            function onIsResponseRequiredChanged() { if (root.flow && root.flow.isResponseRequired) root.checking = false }
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
            MouseArea { anchors.fill: parent }   // swallow clicks

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spaceMd
                spacing: Theme.spaceMd

                // ── head: the shield, the title and the reason ────────────
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
                            text: Theme.icVpn                       // shield-check
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: Theme.accentText
                        }
                    }
                    Column {
                        width: parent.width - Theme.icon2xl - parent.spacing
                        spacing: Theme.spaceXs
                        Text {
                            width: parent.width
                            text: "Authentication required"
                            color: Theme.textPrimary
                            font.family: Theme.type.h3.family
                            font.pixelSize: Theme.type.h3.size
                            font.weight: Theme.type.h3.weight
                            font.letterSpacing: Theme.type.h3.letterSpacing
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: "An app needs administrator rights to make this change."
                            color: Theme.textSecondary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // ── the requester box (new): who is asking, and for what ──
                Rectangle {
                    width: parent.width
                    height: who.implicitHeight + 2 * Theme.spaceS
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    Column {
                        id: who
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spaceS
                        spacing: Theme.spaceXxs
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: root.flow ? (root.flow.message || "") : ""
                            color: Theme.textSecondary
                            font.family: Theme.type.label.family
                            font.pixelSize: Theme.fontSizeS
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: root.flow ? (root.flow.actionId || "") : ""
                            color: Theme.textPrimary
                            font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeS
                            elide: Text.ElideRight
                        }
                    }
                }

                // ── the password field, with its label and helper ─────────
                Column {
                    width: parent.width
                    spacing: Theme.spaceXs

                    Text {
                        text: "Password for " + root.user
                        color: Theme.textPrimary
                        font.family: Theme.type.label.family
                        font.pixelSize: Theme.type.label.size
                        font.weight: Theme.type.label.weight
                    }
                    Rectangle {
                        id: field
                        width: parent.width
                        height: Theme.controlLg
                        radius: Theme.radiusPrimary
                        color: Theme.surfaceSunken
                        border.width: Theme.fieldBorderWidth
                        border.color: root.wrong ? Theme.danger
                                    : pwField.activeFocus ? Theme.focusRing
                                    : fieldMa.containsMouse ? Theme.textMuted : Theme.borderStrong
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        MouseArea { id: fieldMa; anchors.fill: parent; hoverEnabled: true; onClicked: pwField.forceActiveFocus() }

                        Text {
                            id: lockIcon
                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icLock
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: Theme.textMuted
                        }
                        TextInput {
                            id: pwField
                            anchors.left: lockIcon.right; anchors.leftMargin: Theme.spaceXs
                            anchors.right: spin.visible ? spin.left : parent.right
                            anchors.rightMargin: Theme.spaceS
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.checking ? Theme.textDisabled : Theme.textPrimary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            echoMode: (root.flow && root.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                            enabled: root.flow !== null && root.flow.isResponseRequired && !root.checking
                            onAccepted: { root.submit(text); text = "" }
                            Keys.onEscapePressed: if (root.flow) root.flow.cancelAuthenticationRequest()
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pwField.text.length === 0
                                text: (root.flow && root.flow.inputPrompt) ? root.flow.inputPrompt : "Password"
                                color: Theme.textMuted; font: pwField.font
                            }
                        }
                        Spinner {
                            id: spin
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.checking
                            size: Theme.iconMd
                        }
                    }

                    // helper: "Checking…", the system's own message, or the error
                    Row {
                        width: parent.width
                        spacing: Theme.spaceXs
                        visible: helper.text !== ""
                        Text {
                            id: helperIcon
                            anchors.top: parent.top
                            visible: root.wrong || (root.flow !== null && root.flow.supplementaryIsError)
                            width: visible ? Theme.lineHeightXs : 0
                            text: Theme.icWarning
                            font.family: Theme.fontIcons; font.pixelSize: Theme.lineHeightXs
                            color: Theme.danger
                        }
                        Text {
                            id: helper
                            width: parent.width - (helperIcon.visible ? helperIcon.width + parent.spacing : 0)
                            text: root.checking ? "Checking…"
                                : (root.flow && root.flow.supplementaryMessage !== "") ? root.flow.supplementaryMessage
                                : root.wrong ? "Wrong password. Try again."
                                : ""
                            color: (root.wrong || (root.flow && root.flow.supplementaryIsError))
                                   ? Theme.danger : Theme.textMuted
                            font.family: Theme.type.caption.family
                            font.pixelSize: Theme.type.caption.size
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // ── footer: Cancel (ghost) · Authenticate (primary) ───────
                Row {
                    anchors.right: parent.right
                    spacing: Theme.spaceS
                    Rectangle {
                        width: cancelTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                        height: Theme.controlMd
                        radius: Theme.radiusPrimary
                        color: cancelMa.pressed ? Theme.surfacePressed
                             : cancelMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent; text: "Cancel"
                            color: Theme.textPrimary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            font.weight: Theme.fontWeightMedium
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.flow) root.flow.cancelAuthenticationRequest()
                        }
                    }
                    Rectangle {
                        width: okTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                        height: Theme.controlMd
                        radius: Theme.radiusPrimary
                        color: root.checking ? Theme.surfaceRaised
                             : okMa.pressed ? Theme.accentPressed
                             : okMa.containsMouse ? Theme.accentHover : Theme.accent
                        border.color: root.checking ? Theme.borderSubtle : "transparent"
                        border.width: Theme.borderWidth1
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            id: okTxt
                            anchors.centerIn: parent; text: "Authenticate"
                            color: root.checking ? Theme.textDisabled : Theme.onAccent
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            font.weight: Theme.fontWeightMedium
                        }
                        MouseArea {
                            id: okMa
                            anchors.fill: parent; hoverEnabled: true
                            enabled: !root.checking
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.submit(pwField.text); pwField.text = "" }
                        }
                    }
                }
            }
        }
    }
}
