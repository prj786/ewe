import QtQuick

// QsButton — Button (design system: Button) as the Quick settings panel uses
// it: sm in dense rows, md in dialogs; primary · secondary · ghost · danger.
// `go` fires on click; `busy` swaps the glyph for a Spinner.
Rectangle {
    id: qb
    property string label: ""
    property string ic: ""
    property string variant: "secondary"
    property string size: "sm"
    property bool disabled: false
    property bool busy: false
    signal go()
    readonly property bool _sm: qb.size === "sm"
    readonly property color _ink: qb.disabled ? Theme.textDisabled
                                : qb.variant === "primary" ? Theme.onAccent
                                : qb.variant === "danger" ? Theme.onStatus : Theme.textPrimary
    width: qbRow.implicitWidth + 2 * (qb._sm ? Theme.spaceS : Theme.spaceS + Theme.spaceXs)
    height: qb._sm ? Theme.controlSm : Theme.controlMd
    radius: Theme.radiusPrimary
    color: qb.disabled ? (qb.variant === "ghost" ? "transparent" : Theme.surfaceRaised)
         : qb.variant === "primary" ? (qbMa.pressed ? Theme.accentPressed : qbMa.containsMouse ? Theme.accentHover : Theme.accent)
         : qb.variant === "danger" ? (qbMa.pressed ? Qt.tint(Theme.danger, Theme.withAlpha(Theme.textPrimary, 0.24))
                                    : qbMa.containsMouse ? Qt.tint(Theme.danger, Theme.withAlpha(Theme.textPrimary, 0.12)) : Theme.danger)
         : qb.variant === "secondary" ? (qbMa.pressed ? Theme.surfacePressed : qbMa.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised)
         : (qbMa.pressed ? Theme.surfacePressed : qbMa.containsMouse ? Theme.surfaceHover : "transparent")
    border.color: qb.disabled ? (qb.variant === "ghost" ? "transparent" : Theme.borderSubtle)
                : qb.variant === "secondary" ? Theme.borderStrong : "transparent"
    border.width: Theme.borderWidth1
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    Row {
        id: qbRow
        anchors.centerIn: parent
        spacing: Theme.spaceXs
        Spinner {
            visible: qb.busy; anchors.verticalCenter: parent.verticalCenter
            size: qb._sm ? Theme.iconSm : Theme.iconMd
            tone: qb.variant === "primary" ? "on-accent" : "neutral"
        }
        Glyph {
            visible: qb.ic !== "" && !qb.busy; anchors.verticalCenter: parent.verticalCenter
            text: qb.ic; color: qb._ink
            font.pixelSize: qb._sm ? Theme.iconSm : Theme.iconMd
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qb.label; color: qb._ink
            font.family: Theme.type.label.family
            font.pixelSize: qb._sm ? Theme.type.label.size : Theme.type.body.size
            font.weight: Theme.fontWeightMedium
        }
    }
    MouseArea { id: qbMa; anchors.fill: parent; hoverEnabled: true; enabled: !qb.disabled && !qb.busy; cursorShape: Qt.PointingHandCursor; onClicked: qb.go() }
}
