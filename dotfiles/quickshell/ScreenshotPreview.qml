import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// ScreenshotPreview — captured shots pile into a bottom-right STACK
// (visually up to 3 cards, a count badge for more). Each new capture resets the
// shared 5s timer; hovering pauses it. Dragging the stack drops ALL the files.
// screenshot.sh notifies via `qs ipc call preview pop <path>`.
Scope {
    id: root

    property var paths: []
    property bool shown: false
    readonly property int n: paths.length
    readonly property int peeks: Math.min(Math.max(n - 1, 0), 2)   // 0..2 cards behind

    function uriList() {
        var s = ""
        for (var i = 0; i < paths.length; i++) s += "file://" + paths[i] + "\r\n"
        return s
    }

    IpcHandler {
        target: "preview"
        // (not show/hide — those collide with `qs ipc`'s own subcommands)
        function pop(p: string): void {
            var a = root.paths.slice(); a.push(p); root.paths = a
            root.shown = true
            hideTimer.restart()        // any new shot resets the whole stack's 5s
        }
        function dismiss(): void { root.shown = false }
    }

    Timer { id: hideTimer; interval: 5000; onTriggered: root.shown = false }
    // `held` keeps the window mapped through the slide-out; set on SHOW so no
    // signal-order race can unmap it early (see Overview.qml)
    property bool held: false
    Timer { id: gone; interval: Theme.durSlow + 60; onTriggered: { root.held = false; if (!root.shown) root.paths = [] } }
    onShownChanged: if (shown) { gone.stop(); root.held = true } else gone.restart()

    PanelWindow {
        id: win
        visible: (root.shown || root.held) && root.n > 0
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { bottom: true; right: true }
        implicitWidth: 360
        implicitHeight: 240
        mask: Region { item: stack }

        Item {
            id: stack
            width: 280 + 16          // top card + room for the offset peeks
            height: 180 + 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            x: root.shown ? (win.width - width - 16) : (win.width + 16)
            Behavior on x { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.ease } }

            // back peek cards (drawn first → behind), offset down-right
            Repeater {
                model: root.peeks
                delegate: Rectangle {
                    required property int index
                    readonly property int depth: root.peeks - index   // 1 (nearest) .. 2 (farthest)
                    width: 280; height: 180
                    x: depth * 8
                    y: depth * 8
                    radius: Theme.r(12)
                    color: Theme.bg
                    border.color: Theme.stroke
                    border.width: Theme.borderThin
                }
            }

            // top card — the newest capture
            Rectangle {
                id: topCard
                width: 280; height: 180
                radius: Theme.r(12)
                color: Theme.panel
                border.color: Theme.stroke
                border.width: Theme.borderThin
                clip: true

                Image {
                    id: img
                    x: 6; y: 6
                    width: parent.width - 12
                    height: parent.height - 12
                    fillMode: Image.PreserveAspectFit
                    source: root.n > 0 ? "file://" + root.paths[root.n - 1] : ""
                    asynchronous: true
                    cache: false

                    // dragging carries EVERY stacked file as a FILE drag (uri-list
                    // only — no text/plain, or web apps insert the path as text).
                    Drag.active: ma.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.proposedAction: Qt.CopyAction
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    Drag.mimeData: ({ "text/uri-list": root.uriList() })
                }

                // invisible drag target — dragging this (not the image) triggers
                // the external drag while the thumbnail stays put in its box.
                Item { id: dragProxy; width: 1; height: 1; visible: false }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.OpenHandCursor
                    drag.target: dragProxy
                    onEntered: hideTimer.stop()
                    onExited: if (root.shown) hideTimer.restart()
                    onReleased: if (root.shown) hideTimer.restart()
                    // click (no drag) → copy the newest to the clipboard
                    onClicked: if (root.n > 0) Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < '" + root.paths[root.n - 1] + "'"])
                }

                // count badge (shows the real total, even when >3 cards)
                Rectangle {
                    visible: root.n > 1
                    anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 6
                    width: Math.max(20, cnt.implicitWidth + 12); height: 20; radius: 10
                    color: Theme.accent
                    Text { id: cnt; anchors.centerIn: parent; text: root.n; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.Bold }
                }

                // hover hint
                Rectangle {
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                    width: hintTxt.implicitWidth + 14; height: 20; radius: 10
                    color: Theme.shadow
                    visible: ma.containsMouse
                    Text {
                        id: hintTxt
                        anchors.centerIn: parent
                        text: root.n > 1 ? "drag all ↗" : "drag · click=copy"
                        color: Theme.fg
                        font.family: Theme.fontText; font.pixelSize: 10
                    }
                }
            }
        }
    }
}
