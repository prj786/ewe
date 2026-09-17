import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Toast — confirms something that just happened and offers one quick way
// back, such as Undo (design system: Toast). NOT a notification: messages
// from apps are Notifications.qml, and an error that needs a decision is a
// dialog.
//
//   placement  centred at the bottom of the screen, spaceS + spaceXs (12)
//              above the dock, or windowGap above the edge when the dock is
//              away; the overlay layer, above popups
//   container  surfaceOverlay with a borderWidth1 borderSubtle outline, the
//              radiusRounded corner and the shadowFloat elevation, at least
//              controlXl (40) tall and at most panelLg (560) wide, with
//              spaceS + spaceXs of padding on the left and spaceXs elsewhere
//   icon       iconMd in textSecondary, or the status colour for success,
//              warning and danger; a Spinner while something is in progress
//   message    the body style in textPrimary, one line, sentence case —
//              StyledText, so the thing itself can be named in <b>
//   action     one, the body-strong style in accentText, controlLg tall on
//              the radiusPrimary corner; hover surfaceHover, and the focus
//              ring inside its edge
//   close      a borderWidth1 divider and a ghost icon button
//   timer      a borderWidth2 accent line along the bottom that shrinks
//              while the toast waits, and pauses while it is hovered
//
// ONE at a time: a new toast replaces the one on screen, and the replaced
// action is gone with it (the card's rule — the shell does not stack them).
// It stays 5 seconds, or 8 with an action. It never takes focus by itself;
// clicking it gives it focus, and Esc then closes it.
//
//     Globals.toast("Moved <b>report.pdf</b> to Trash",
//                   { actionLabel: "Undo", action: function () { … } })
//     qs ipc call toast post "Copied to clipboard"
//     qs ipc call toast action "Moved 3 windows" Undo "hyprctl dispatch …"
Scope {
    id: root

    property string message: ""
    property string icon: ""
    property string tone: ""              // "" · success · warning · danger · info · busy
    property string actionLabel: ""
    property var action: null             // a function, run when the action is chosen
    property string actionCommand: ""     // …or a shell command, for the IPC form
    property int timeout: 0               // 0 = the card's 5 s, or 8 s with an action
    property bool shown: false
    signal closed()

    readonly property int defaultTimeout: root.actionLabel !== "" ? 8000 : 5000
    property int _total: 5000
    property real _left: 0
    readonly property bool _paused: hoverMa.containsMouse || actionBtn.activeFocus || closeBtn.activeFocus

    function show(text, opts) {
        var o = opts || {}
        root.message = text
        root.icon = o.icon !== undefined ? o.icon : ""
        root.tone = o.tone !== undefined ? o.tone : ""
        root.actionLabel = o.actionLabel !== undefined ? o.actionLabel : ""
        root.action = o.action !== undefined ? o.action : null
        root.actionCommand = o.command !== undefined ? o.command : ""
        root.timeout = o.timeout !== undefined ? o.timeout : 0
        root._total = root.timeout > 0 ? root.timeout : root.defaultTimeout
        root._left = root._total
        root.shown = true
    }
    function hide() {
        if (!root.shown)
            return
        root.shown = false
        root.closed()
    }
    // the action, from the button, from Super+Z, or from `ipc call toast undo`
    function runAction() {
        if (root.actionLabel === "")
            return
        var fn = root.action, cmd = root.actionCommand
        root.hide()
        if (typeof fn === "function") fn()
        else if (cmd !== "") Quickshell.execDetached(["sh", "-c", cmd])
    }

    // Public API. `action` takes a shell command, because an out-of-process
    // caller has no function to hand over.
    IpcHandler {
        target: "toast"
        // `post`, not `show`: `qs ipc call <target> show` collides with the
        // `qs ipc show` subcommand and silently lists targets instead.
        function post(message: string): void { root.show(message, {}) }
        function show(message: string): void { root.show(message, {}) }
        function action(message: string, label: string, command: string): void {
            root.show(message, { actionLabel: label, command: command })
        }
        function undo(): void { root.runAction() }
        function hide(): void { root.hide() }
    }

    // the in-shell entry point: Globals.toast(…) routes here
    Component.onCompleted: Globals.toastHost = root
    Component.onDestruction: if (Globals.toastHost === root) Globals.toastHost = null

    // the countdown, paused while the toast is hovered or focused
    Timer {
        interval: 50; repeat: true
        running: root.shown && !root._paused
        onTriggered: {
            root._left -= interval
            if (root._left <= 0) root.hide()
        }
    }

    PanelWindow {
        id: win
        visible: root.shown || card.opacity > 0.01
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:toast"
        WlrLayershell.layer: WlrLayer.Overlay
        // it never takes focus on its own; clicking it hands focus over, and
        // Esc then closes it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { left: true; right: true; bottom: true }
        implicitHeight: Theme.control2xl + Theme.spaceLg
        // only the card takes pointer input; the rest passes through
        mask: Region { item: card }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            // the dock's own layer reserves its height, so this margin is
            // measured from the dock's edge
            anchors.bottomMargin: (Globals.dockEnabled && !Globals.dockAutohide)
                                  ? Theme.spaceS + Theme.spaceXs : Theme.windowGap
            width: Math.min(Theme.panelLg, row.implicitWidth + Theme.spaceS + Theme.spaceXs + Theme.spaceXs)
            height: Math.max(Theme.controlXl, row.implicitHeight + 2 * Theme.spaceXs)
            radius: Theme.radiusRounded
            color: Theme.surfaceOverlay
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1

            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.shown ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            layer.enabled: true
            layer.effect: Elevation {}
            // fade plus a slideOffset lift; Reduce motion zeroes the slide
            transform: Translate {
                y: root.shown ? 0 : Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }

            Keys.onEscapePressed: root.hide()
            MouseArea { id: hoverMa; anchors.fill: parent; hoverEnabled: true }

            Row {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
                spacing: Theme.spaceS

                Text {
                    visible: root.icon !== "" && root.tone !== "busy"
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icon
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                    color: root.tone === "success" ? Theme.success
                         : root.tone === "warning" ? Theme.warning
                         : root.tone === "danger" ? Theme.danger
                         : root.tone === "info" ? Theme.info : Theme.textSecondary
                }
                Spinner {
                    visible: root.tone === "busy"
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.iconMd
                }
                Text {
                    id: msg
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth,
                                    Theme.panelLg - Theme.spaceLg - actionBtn.width - closeBtn.width)
                    text: root.message
                    textFormat: Text.StyledText
                    color: Theme.textPrimary
                    font.family: Theme.type.body.family
                    font.pixelSize: Theme.type.body.size
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: actionBtn
                    visible: root.actionLabel !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? actionTxt.implicitWidth + 2 * Theme.spaceS : 0
                    height: Theme.controlLg
                    radius: Theme.radiusPrimary
                    color: aMa.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    activeFocusOnTab: root.actionLabel !== ""
                    Keys.onSpacePressed: root.runAction()
                    Keys.onReturnPressed: root.runAction()
                    // the action's focus ring sits inside its own edge
                    border.color: actionBtn.activeFocus ? Theme.focusRing : "transparent"
                    border.width: actionBtn.activeFocus ? Theme.focusWidth : 0
                    Text {
                        id: actionTxt
                        anchors.centerIn: parent
                        text: root.actionLabel
                        color: Theme.accentText
                        font.family: Theme.type.bodyStrong.family
                        font.pixelSize: Theme.type.bodyStrong.size
                        font.weight: Theme.fontWeightSemibold
                    }
                    MouseArea {
                        id: aMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction()
                    }
                }
                Rectangle {
                    visible: root.actionLabel !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.borderWidth1; height: Theme.iconLg
                    color: Theme.borderSubtle
                }
                Rectangle {
                    id: closeBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.controlMd; height: Theme.controlMd
                    radius: Theme.radiusPrimary
                    color: cMa.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    activeFocusOnTab: true
                    Keys.onSpacePressed: root.hide()
                    Keys.onReturnPressed: root.hide()
                    border.color: closeBtn.activeFocus ? Theme.focusRing : "transparent"
                    border.width: closeBtn.activeFocus ? Theme.focusWidth : 0
                    Text {
                        anchors.centerIn: parent
                        text: Theme.icClose
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                        color: Theme.textSecondary
                    }
                    MouseArea {
                        id: cMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.hide()
                    }
                }
            }

            // the timer line: it shrinks while the toast waits
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.border.width
                anchors.left: parent.left
                anchors.leftMargin: parent.border.width
                height: Theme.borderWidth2
                width: (parent.width - 2 * parent.border.width)
                       * Math.max(0, Math.min(1, root._total > 0 ? root._left / root._total : 0))
                color: Theme.accent
                bottomLeftRadius: Theme.rIn(Theme.radiusRounded, parent.border.width)
            }
        }
    }
}
