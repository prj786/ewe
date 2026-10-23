import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// The Minimized panel (dock 1.2.0) — the windows Super+Z sent away
// (special:minimized; the retired Pen's special:pen counts too), as
// thumbnails over the dock's Minimized box. Click one to bring it back to
// the workspace you are on; ✕ closes it; "Restore all" brings back every one.
//
// Each thumbnail is ONE captured frame (`live: false`), taken while the panel
// shows: Hyprland renders a window on a hidden workspace for a toplevel
// capture all the same, and nothing is captured while the panel is shut. A
// capture must never race its window's close (Hyprland 0.56 disconnects the
// whole shell — "invalid object N"), so ✕ drops the capture first and closes
// the window a beat later, like the Overview's.
Scope {
    id: mz
    // the Dock root: minWins, restore(), restoreAll(), closeWin(), iconFor(), titleOf()
    required property var host

    readonly property bool open: pop.open
    function toggleAt(a) { pop.toggleAt(a) }
    function close() { pop.close() }

    // captures exist while the card shows, and through its close fade
    property bool shown: false
    Timer { id: fadeHold; interval: Math.max(1, Theme.durBase); onTriggered: mz.shown = false }

    readonly property var wins: mz.host.minWins
    // nothing left to show: the panel goes with the last window
    onWinsChanged: if (mz.wins.length === 0) pop.close()

    readonly property int gap: Theme.spaceMd
    readonly property int pad: Theme.spaceMd
    readonly property int cols: Math.max(1, Math.min(4, mz.wins.length))
    readonly property int rows: Math.max(1, Math.ceil(mz.wins.length / mz.cols))
    readonly property int cellW: Math.round(Theme.panelSm / 2)
    readonly property int thumbH: Math.round(mz.cellW * 5 / 8)
    readonly property int cellH: mz.thumbH + Theme.spaceS + Theme.controlMd
    readonly property int headH: Theme.controlLg

    AnchoredPopup {
        id: pop
        name: "minimized"
        // its own token, so the dock's other panels and this one close each
        // other through Shell.closePopups like any two plugin popups
        owner: "ewe.dock.minimized"
        action: "ewe.dock.minimized"
        implicitWidth: mz.cols * mz.cellW + (mz.cols - 1) * mz.gap + 2 * mz.pad
        implicitHeight: mz.pad + mz.headH + Theme.spaceS + mz.rows * mz.cellH + (mz.rows - 1) * mz.gap + mz.pad
        onOpened: { fadeHold.stop(); mz.shown = true }
        onClosed: fadeHold.restart()

        Item {
            anchors.fill: parent
            anchors.margins: mz.pad

            // header: the title and "Restore all"
            Item {
                id: head
                width: parent.width; height: mz.headH
                TextStrong {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Minimized"
                }
                QsButton {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    visible: mz.wins.length > 1
                    variant: "ghost"
                    label: "Restore all"
                    onGo: { mz.host.restoreAll(); pop.close() }
                }
            }

            Grid {
                anchors.top: head.bottom; anchors.topMargin: Theme.spaceS
                columns: mz.cols
                columnSpacing: mz.gap; rowSpacing: mz.gap

                Repeater {
                    model: mz.wins
                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: mz.cellW; height: mz.cellH
                        readonly property bool hot: cellMa.containsMouse || closeMa.containsMouse
                        property bool closing: false
                        Timer { id: closeLater; interval: Math.max(1, Theme.durFast); onTriggered: mz.host.closeWin(cell.modelData) }

                        // the window's shape, fitted into the cell's thumbnail box
                        readonly property real aspect: {
                            if (sc.hasContent && sc.sourceSize.height > 0) return sc.sourceSize.width / sc.sourceSize.height
                            var o = cell.modelData.lastIpcObject
                            return (o && o.size && o.size[1] > 0) ? o.size[0] / o.size[1] : mz.cellW / mz.thumbH
                        }
                        readonly property real tw: cell.aspect >= mz.cellW / mz.thumbH ? mz.cellW : Math.round(mz.thumbH * cell.aspect)
                        readonly property real th: cell.aspect >= mz.cellW / mz.thumbH ? Math.round(mz.cellW / cell.aspect) : mz.thumbH

                        RectangularShadow {
                            anchors.fill: thumb
                            radius: Theme.radiusPrimary
                            offset.x: Theme.shadowFloat.x; offset.y: Theme.shadowFloat.y
                            blur: Theme.shadowFloat.blur
                            color: Theme.shadowFloat.color
                        }
                        ClippingRectangle {
                            id: thumb
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.round((mz.thumbH - cell.th) / 2)
                            width: cell.tw; height: cell.th
                            radius: Theme.radiusPrimary
                            color: Theme.surfaceSunken
                            // lifts a step on hover, like a dock tile
                            scale: cell.hot && !Theme.reduceMotion ? 1.04 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                            ScreencopyView {
                                id: sc
                                anchors.fill: parent
                                visible: hasContent
                                captureSource: (mz.shown && !cell.closing && cell.modelData.wayland) || null
                                live: false
                            }
                            Image {
                                anchors.centerIn: parent
                                visible: !sc.hasContent
                                width: Theme.icon3xl; height: Theme.icon3xl
                                sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl; mipmap: true
                                source: mz.host.iconFor(cell.modelData)
                            }
                        }
                        // the hover ring
                        Rectangle {
                            anchors.fill: thumb
                            anchors.margins: -Theme.borderWidth2
                            scale: thumb.scale
                            visible: cell.hot
                            color: "transparent"
                            radius: Theme.radiusPrimary + Theme.borderWidth2
                            border.color: Theme.accent
                            border.width: Theme.borderWidth2
                        }
                        // the app, on the thumbnail's corner (the dock's own idiom)
                        Image {
                            anchors.right: thumb.right; anchors.bottom: thumb.bottom
                            anchors.rightMargin: -Theme.spaceXs; anchors.bottomMargin: -Theme.spaceXs
                            width: Theme.iconXl; height: Theme.iconXl
                            sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl; mipmap: true
                            source: mz.host.iconFor(cell.modelData)
                        }
                        TextCaption {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Theme.controlMd
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: mz.host.titleOf(cell.modelData)
                            color: cell.hot ? Theme.textPrimary : Theme.textSecondary
                        }

                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { mz.host.restore(cell.modelData); pop.close() }
                        }
                        // close — top-left of the thumbnail, on hover
                        Rectangle {
                            x: thumb.x + Theme.spaceXs; y: thumb.y + Theme.spaceXs
                            width: Theme.controlSm; height: Theme.controlSm
                            radius: Theme.radiusFull
                            visible: cell.hot
                            color: closeMa.containsMouse ? Theme.danger : Theme.glassRaised
                            border.color: closeMa.containsMouse ? Theme.danger : Theme.glassBorder
                            border.width: Theme.borderWidth1
                            Text {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
                                color: closeMa.containsMouse ? Theme.onStatus : Theme.textPrimary
                            }
                            MouseArea {
                                id: closeMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { cell.closing = true; closeLater.restart() }
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Restore " + mz.host.titleOf(cell.modelData)
                    }
                }
            }
        }
    }
}
