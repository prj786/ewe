import QtQuick

// BarSep — the bar's own divider: borderWidth1 × iconMd, spaceXs each side.
Item {
    implicitWidth: Theme.borderWidth1 + 2 * Theme.spaceXs
    implicitHeight: Theme.barLarge ? Theme.iconLg : Theme.iconMd
    Rectangle {
        anchors.centerIn: parent
        width: Theme.borderWidth1; height: parent.height
        color: Theme.barOutline
    }
}
