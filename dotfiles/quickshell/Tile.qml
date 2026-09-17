import QtQuick

// Tile — the quick settings tile (design system: Quick settings tile): it
// toggles a feature, shows its state, and can open that feature's details
// inside the panel.
//
//   tile     control2xl + spaceS (56) tall, surfaceOverlay with a
//            borderWidth1 borderSubtle outline and the radiusRounded corner;
//            `small` is the control2xl (48), icon-only form
//   icon     a controlLg circle — surfaceHover off, accent with an onAccent
//            glyph on; a Spinner takes its place while a change applies
//   text     title (body-strong) over the status (caption): the connected
//            network, the device, "Off", "Until 07:00"
//   details  a controlMd zone on the right with a chevron, divided by a
//            borderWidth1 line (`hasMenu`)
//
//   on            accentSubtle fill, no outline, status in accentText
//   hover         the part under the pointer fills with surfaceHover
//   details open  a borderWidth2 accentText edge
//   focus         a focusWidth focusRing, focusWidth outside the edge
//   disabled      textDisabled, with the reason as the status ("No adapter")
//
// TWO independent states, never conflated: `active` is the SERVICE ("Wi-Fi
// is on"), `opened` is its list being expanded. The split button is what
// lets Wi-Fi be switched off without ever opening the network list.
// Sized for a two-up Row: half the parent minus the Row's own spacing.
Rectangle {
    id: tile
    property string ic: ""
    property string label: ""
    property string sub: ""
    property bool active: false
    property bool opened: false
    property bool hasMenu: false
    property bool busy: false            // section is loading (scan in flight)
    property bool disabled: false
    property bool small: false           // icon only, control2xl tall
    property int gap: Theme.spaceS       // the grid gap, when the parent has none
    signal clicked()                     // body
    signal menu()                        // detail zone

    readonly property int _detail: Theme.controlMd
    readonly property color _ink: tile.disabled ? Theme.textDisabled : Theme.textPrimary

    width: parent ? (parent.width - (parent.spacing !== undefined ? parent.spacing : tile.gap)) / 2
                  : Theme.panelSm / 2
    height: tile.small ? Theme.control2xl : Theme.control2xl + Theme.spaceS
    radius: Theme.radiusRounded
    color: tile.active ? Theme.accentSubtle : Theme.surfaceOverlay
    // `on` drops the outline; an open detail zone draws a heavy accent edge
    border.color: tile.opened ? Theme.accentText : Theme.borderSubtle
    border.width: tile.opened ? Theme.borderWidth2 : (tile.active ? 0 : Theme.borderWidth1)
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

    activeFocusOnTab: !tile.disabled
    Keys.onSpacePressed: if (!tile.disabled) tile.clicked()
    Keys.onReturnPressed: if (!tile.disabled) tile.clicked()

    // ── the body: icon, title, status ─────────────────────────────────────
    Rectangle {
        id: body
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: tile.border.width
        anchors.rightMargin: tile.border.width + (tile.hasMenu ? tile._detail : 0)
        color: (bodyMa.containsMouse && !tile.disabled) ? Theme.surfaceHover : "transparent"
        // rounds only the corners it shares with the tile, inset by the rule
        radius: 0
        topLeftRadius: Theme.rIn(Theme.radiusRounded, tile.border.width)
        bottomLeftRadius: Theme.rIn(Theme.radiusRounded, tile.border.width)
        topRightRadius: tile.hasMenu ? 0 : topLeftRadius
        bottomRightRadius: tile.hasMenu ? 0 : topLeftRadius
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
            spacing: Theme.spaceS
            Rectangle {
                id: circle
                width: Theme.controlLg; height: Theme.controlLg
                radius: Theme.radiusFull
                anchors.verticalCenter: parent.verticalCenter
                color: tile.disabled ? Theme.surfaceHover
                     : tile.active ? Theme.accent : Theme.surfaceHover
                antialiasing: true
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Text {
                    anchors.centerIn: parent
                    visible: !tile.busy
                    text: tile.ic
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                    color: tile.disabled ? Theme.textDisabled
                         : tile.active ? Theme.onAccent : Theme.textPrimary
                }
                // busy: the circle carries the spinner, so the tile keeps its shape
                Spinner {
                    anchors.centerIn: parent
                    visible: tile.busy
                    size: Theme.iconMd
                    tone: tile.active ? "on-accent" : "accent"
                }
            }
            Column {
                visible: !tile.small
                width: parent.width - circle.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    text: tile.label
                    color: tile._ink
                    font.family: Theme.type.bodyStrong.family
                    font.pixelSize: Theme.type.bodyStrong.size
                    font.weight: Theme.type.bodyStrong.weight
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: tile.sub !== ""
                    text: tile.sub
                    color: tile.disabled ? Theme.textDisabled
                         : tile.active ? Theme.accentText : Theme.textMuted
                    font.family: Theme.type.caption.family
                    font.pixelSize: Theme.type.caption.size
                    font.weight: Theme.type.caption.weight
                    elide: Text.ElideRight
                }
            }
        }
        MouseArea {
            id: bodyMa
            anchors.fill: parent
            enabled: !tile.disabled
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            // right-clicking the tile opens its details, like the detail zone
            onClicked: function (m) {
                if (m.button === Qt.RightButton && tile.hasMenu) tile.menu()
                else tile.clicked()
            }
        }
    }

    // ── the detail zone: its own hover, its own hit area ──────────────────
    Rectangle {
        id: detail
        visible: tile.hasMenu
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.margins: tile.border.width
        width: tile._detail
        color: (chevMa.containsMouse && !tile.disabled) ? Theme.surfaceHover : "transparent"
        radius: 0
        topRightRadius: Theme.rIn(Theme.radiusRounded, tile.border.width)
        bottomRightRadius: topRightRadius
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        // the line that divides the two halves of the split button
        Rectangle {
            width: Theme.borderWidth1; height: parent.height
            anchors.left: parent.left
            color: Theme.borderSubtle
        }
        Text {
            id: caret
            anchors.centerIn: parent
            text: Theme.icChevronRight
            rotation: tile.opened ? 90 : 0
            Behavior on rotation {
                NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durFast; easing.type: Theme.easeFast }
            }
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
            color: tile.disabled ? Theme.textDisabled
                 : tile.opened ? Theme.accentText : Theme.textSecondary
        }
        MouseArea {
            id: chevMa
            anchors.fill: parent
            enabled: !tile.disabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.menu()
        }
    }

    // the focus ring sits outside the tile's edge
    Rectangle {
        anchors.fill: parent
        anchors.margins: -(tile.border.width + Theme.focusWidth)
        radius: Theme.radiusRounded
        color: "transparent"
        visible: tile.activeFocus
        border.color: Theme.focusRing
        border.width: Theme.focusWidth
        antialiasing: true
    }
}
