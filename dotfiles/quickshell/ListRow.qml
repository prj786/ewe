import QtQuick

// ListRow — one row of a list: a network, a device, a file, a setting with
// its control (design system: List row). Lives inside a ListWell.
//
//   height   controlLg (32) by default; `density: "dense"` gives controlMd
//            (28) for files and menus inside panels, "tall" control2xl (48)
//            for rows with app icons and launcher results. A row with a
//            description grows past its minimum instead of clipping.
//   leading  an iconMd glyph in textSecondary (accentText when selected)
//   text     title (body) over an optional description (caption, textMuted)
//   trailing children first, then the built-in caption / spinner / tick,
//            spaceS apart
//   states   hover surfaceHover · pressed surfacePressed · selected
//            accentSubtle · active (the connected network) weight medium ·
//            disabled everything in textDisabled, no hover, no click
//   focus    a focusWidth focusRing on the row's edge, drawn inside it
//            because the row sits in a well
//
// Extra trailing content declared as children lands in a Row at the right
// edge, left of the built-ins; its own MouseAreas sit above the row's, so
// they win the click.
//     ListRow { glyph: Theme.icWifi; label: ssid; desc: "Open network"
//               selected: active; check: active; onClicked: … }
Item {
    id: row
    property string glyph: ""
    property string label: ""
    property string desc: ""             // second line: caption, textMuted
    property string kind: ""             // quiet right-hand caption ("open", "1 Gb/s")
    property bool selected: false
    property bool active: false          // the item in use — title at medium weight
    property bool disabled: false
    property bool check: false           // tick at the right edge
    property bool busy: false            // spinner in the tick's place
    property string density: "default"   // dense (28) · default (32) · tall (48)
    property color glyphColor: row.disabled ? Theme.textDisabled
                             : row.selected ? Theme.accentText : Theme.textSecondary
    property int glyphSize: Theme.iconMd
    default property alias trailing: trail.data
    readonly property alias hovered: ma.containsMouse
    signal clicked()

    readonly property int _minHeight: row.density === "dense" ? Theme.controlMd
                                    : row.density === "tall" ? Theme.control2xl : Theme.controlLg
    readonly property int _padH: Theme.spaceS
    readonly property int _padV: Theme.spaceXs
    readonly property int _gap: row.density === "dense" ? Theme.spaceS : Theme.spaceS + Theme.spaceXs

    width: parent ? parent.width : Theme.panelSm
    height: Math.max(_minHeight, texts.implicitHeight + 2 * _padV)
    activeFocusOnTab: !row.disabled
    Keys.onSpacePressed: if (!row.disabled) row.clicked()
    Keys.onReturnPressed: if (!row.disabled) row.clicked()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSecondary
        color: row.disabled ? "transparent"
             : ma.pressed ? Theme.surfacePressed
             : row.selected ? Theme.accentSubtle
             : ma.containsMouse ? Theme.surfaceHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        // the focus ring rides the row's own edge (it is inside a well)
        border.color: row.activeFocus ? Theme.focusRing : "transparent"
        border.width: row.activeFocus ? Theme.focusWidth : 0
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: !row.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
    Text {
        id: lead
        visible: row.glyph !== ""
        width: visible ? Theme.iconMd : 0
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left; anchors.leftMargin: row._padH
        anchors.verticalCenter: parent.verticalCenter
        text: row.glyph
        font.family: Theme.fontIcons; font.pixelSize: row.glyphSize
        color: row.glyphColor
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    Column {
        id: texts
        anchors.left: parent.left
        anchors.leftMargin: row._padH + (row.glyph !== "" ? lead.width + row._gap : 0)
        anchors.right: trail.left; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: row.label
            color: row.disabled ? Theme.textDisabled : Theme.textPrimary
            font.family: Theme.type.body.family
            font.pixelSize: Theme.type.body.size
            font.weight: (row.active || row.selected) ? Theme.fontWeightMedium : Theme.type.body.weight
            elide: Text.ElideRight
        }
        Text {
            visible: row.desc !== ""
            width: parent.width
            text: row.desc
            color: row.disabled ? Theme.textDisabled : Theme.textMuted
            font.family: Theme.type.caption.family
            font.pixelSize: Theme.type.caption.size
            font.weight: Theme.type.caption.weight
            elide: Text.ElideRight
        }
    }
    Row {
        id: trail
        anchors.right: builtins.left
        anchors.rightMargin: builtins.width > 0 ? Theme.spaceS : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceS
    }
    Row {
        id: builtins
        anchors.right: parent.right; anchors.rightMargin: row._padH
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceS
        Text {
            visible: row.kind !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: row.kind
            color: row.disabled ? Theme.textDisabled : Theme.textMuted
            font.family: Theme.type.caption.family
            font.pixelSize: Theme.type.caption.size
            font.weight: Theme.type.caption.weight
        }
        Spinner { visible: row.busy; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconMd }
        Text {
            visible: row.check && !row.busy
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.icCheck
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
            color: row.disabled ? Theme.textDisabled : Theme.accentText
        }
    }
}
