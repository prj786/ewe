import QtQuick
import qs

// Well — one section of the card: surfaceOverlay with a borderSubtle edge on
// the radiusRounded corner, spaceS + spaceXxs (10) by spaceS + spaceXs (12)
// of padding, its rows spaceXs + spaceXxs (6) apart.
Rectangle {
    id: well
    default property alias content: col.data
    readonly property int padH: Theme.spaceS + Theme.spaceXs
    readonly property int padV: Theme.spaceS + Theme.spaceXxs
    implicitHeight: col.implicitHeight + 2 * well.padV
    radius: Theme.radiusRounded
    color: Theme.surfaceOverlay
    border.color: Theme.borderSubtle
    border.width: Theme.borderWidth1
    Column {
        id: col
        x: well.padH; y: well.padV
        width: well.width - 2 * well.padH
        spacing: Theme.spaceXs + Theme.spaceXxs
    }
}
