import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs

// ewe.screenshot — Preview: captured shots pile into a bottom-right STACK
// (visually up to 3 cards, a count badge for more). Each new capture resets
// the shared 5s timer; hovering pauses it. Dragging the stack drops ALL the
// files. screenshot.sh (in this plugin) notifies via
//     qs ipc call ewe.screenshot pop <path>
// and the keybinds in manifest.json call `shoot full|region|activewindow`.
Scope {
    id: root
    property var settings: ({})         // {copy: bool} — also copy the shot to the clipboard
    readonly property string script: Qt.resolvedUrl("screenshot.sh").toString().replace(/^file:\/\//, "")
    function shoot(mode) {
        Quickshell.execDetached(["sh", "-c", 'EWE_SHOT_COPY="$2" exec "$1" "$3"', "_", root.script, root.settings.copy === false ? "0" : "1", mode])
    }

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
        target: "ewe.screenshot"
        // (not show/hide — those collide with `qs ipc`'s own subcommands)
        function shoot(mode: string): void { root.shoot(mode) }
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
        WlrLayershell.namespace: "quickshell:ewe.screenshot"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { bottom: true; right: true }
        implicitWidth: stack.width + 2 * Theme.spaceMd
        implicitHeight: stack.height + 2 * Theme.spaceMd
        mask: Region { item: stack }

        Item {
            id: stack
            // the top card is a screen-shaped thumbnail; each card behind it
            // peeks spaceS further down and right
            readonly property int cardW: Theme.panelSm - 2 * Theme.spaceLg
            readonly property int cardH: Math.round(cardW * 9 / 16)
            width: cardW + 2 * Theme.spaceS
            height: cardH + 2 * Theme.spaceS
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceMd
            x: root.shown ? (win.width - width - Theme.spaceMd) : (win.width + Theme.spaceMd)
            Behavior on x { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeSlow } }

            // back peek cards (drawn first → behind), offset down-right
            Repeater {
                model: root.peeks
                delegate: Rectangle {
                    required property int index
                    readonly property int depth: root.peeks - index   // 1 (nearest) .. 2 (farthest)
                    width: stack.cardW; height: stack.cardH
                    x: depth * Theme.spaceS
                    y: depth * Theme.spaceS
                    radius: Theme.radiusRounded
                    color: Theme.surfaceBase
                    border.color: Theme.borderSubtle
                    border.width: Theme.borderWidth1
                }
            }

            // top card — the newest capture (a Card: surfaceRaised, a
            // borderSubtle outline, radiusRounded, the float shadow)
            Rectangle {
                id: topCard
                width: stack.cardW; height: stack.cardH
                radius: Theme.radiusRounded
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                clip: true
                layer.enabled: true
                layer.effect: Elevation {}

                Image {
                    id: img
                    x: Theme.spaceXs + Theme.spaceXxs; y: x
                    width: parent.width - 2 * x
                    height: parent.height - 2 * y
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

                // count badge (shows the real total, even when >3 cards):
                // the shell's solid accent Badge
                Badge {
                    visible: root.n > 1
                    anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.spaceS
                    count: root.n
                    tone: "accent"; solid: true
                }

                // hover hint: a Tag (sm) on the overlay surface, readable
                // over any screenshot in either scheme
                Rectangle {
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.spaceS
                    width: hintTxt.implicitWidth + 2 * Theme.spaceS; height: Theme.controlSm; radius: Theme.radiusFull
                    color: Theme.surfaceOverlay
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    visible: ma.containsMouse
                    Text {
                        id: hintTxt
                        anchors.centerIn: parent
                        text: root.n > 1 ? "Drag all" : "Drag, or click to copy"
                        color: Theme.textPrimary
                        font.family: Theme.type.caption.family; font.pixelSize: Theme.type.caption.size
                    }
                }
            }
        }
    }
}
