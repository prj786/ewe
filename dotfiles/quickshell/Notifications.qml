import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Notifications — Quickshell IS the notification server now (replaces swaync).
// Live toasts appear top-right (unless DND), GROUPED by app: several notifications
// from the same app stack into one card with a count. Clicking a toast focuses the
// window it came from (via its default action, falling back to focusing the app's
// window in Hyprland) and dismisses the group. The full list lives in the control
// centre. The server is shared via Globals.server.
Scope {
    id: root

    property var popups: []
    property var groups: []   // [{ app, items:[n…], latest:n }] derived from popups

    function pushPopup(n) { var a = root.popups.slice(); a.push(n); root.popups = a; root.rebuild() }
    function removePopup(n) { root.popups = root.popups.filter(function (x) { return x !== n }); root.rebuild() }
    function removeGroup(grp) { root.popups = root.popups.filter(function (x) { return grp.items.indexOf(x) < 0 }); root.rebuild() }

    function rebuild() {
        var by = {}, order = []
        for (var i = 0; i < root.popups.length; i++) {
            var n = root.popups[i], k = String(n.appName || "Notification")
            if (!by[k]) { by[k] = { app: k, items: [] }; order.push(k) }
            by[k].items.push(n)
        }
        var gs = []
        for (var j = 0; j < order.length; j++) { var grp = by[order[j]]; grp.latest = grp.items[grp.items.length - 1]; gs.push(grp) }
        root.groups = gs
    }

    // Focus the window a notification came from: SWITCH to its workspace and raise
    // it. `hyprctl dispatch focuswindow` follows the match to whatever workspace the
    // window lives on, so this lands you on the right desktop with the window focused.
    function focusFrom(n) {
        // Match a Hyprland window by class derived from the desktop-entry / app name.
        // Try the desktop-entry first (most reliable: it's the app id), then appName.
        var cands = []
        if (n.desktopEntry && String(n.desktopEntry).length) cands.push(String(n.desktopEntry))
        if (n.appName && String(n.appName).length) cands.push(String(n.appName))
        for (var c = 0; c < cands.length; c++) {
            var seg = cands[c].split(".").pop().replace(/[^A-Za-z0-9]/g, "")
            if (seg.length) {
                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "class:(?i).*" + seg + ".*"])
                break
            }
        }
        // Also fire the app's "default" action (opens the relevant message/thread)
        // — after the focus dispatch, so the app acts on the now-current window.
        try {
            if (n.actions) for (var i = 0; i < n.actions.length; i++)
                if (n.actions[i].identifier === "default") { n.actions[i].invoke(); break }
        } catch (e) {}
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true
        Component.onCompleted: Globals.server = server
        onNotification: function (n) {
            n.tracked = true                 // keep in trackedNotifications (history)
            if (!Globals.dnd) Globals.playSound("message-new-instant")
            if (!Globals.dnd) root.pushPopup(n)
        }
    }

    // ── grouped toast stack, top-right, below the bar ─────────────────────────
    PanelWindow {
        visible: root.groups.length > 0 && !Globals.dnd
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors { top: true; right: true; left: true; bottom: true }

        // Only the toast column grabs pointer input; the rest is click-through.
        mask: Region { item: toastColumn }

        Column {
            id: toastColumn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 5   // hugs the bar: the layer already sits below its exclusive zone
            anchors.rightMargin: 10
            spacing: 8
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Theme.ease }
                NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Theme.durBase; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }
            move: Transition {
                NumberAnimation { properties: "x,y"; duration: Theme.durBase; easing.type: Theme.ease }
            }

            Repeater {
                model: root.groups
                delegate: Item {
                    id: groupItem
                    required property var modelData
                    readonly property var latest: modelData.latest
                    readonly property int count: modelData.items.length
                    width: 360
                    height: card.height + (count > 1 ? 6 : 0)

                    // expire the whole group together (latest notification's timeout)
                    Timer {
                        running: true
                        interval: groupItem.latest.expireTimeout > 0 ? groupItem.latest.expireTimeout : 5000
                        onTriggered: root.removeGroup(groupItem.modelData)
                    }

                    // stacked-card hint behind the main card when there are several
                    Rectangle {
                        visible: groupItem.count > 1
                        anchors.top: parent.top; anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 14; height: card.height
                        radius: Theme.radiusInner; color: Theme.bg1; opacity: 0.55
                        border.color: Theme.stroke2; border.width: Theme.borderThin
                    }

                    Rectangle {
                        id: card
                        width: parent.width
                        height: col.implicitHeight + 24
                        radius: Theme.radiusInner
                        color: Theme.bg1
                        border.color: Theme.stroke2
                        border.width: Theme.borderThin
                        layer.enabled: true
                        layer.effect: Elevation {}
                        Sheen { radius: parent.radius }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12
                            Image {
                                width: 38; height: 38
                                sourceSize.width: 76; sourceSize.height: 76; mipmap: true
                                visible: source != ""
                                source: {
                                    var n = groupItem.latest
                                    if (n.image && n.image != "") return n.image
                                    if (n.appIcon && n.appIcon != "") return Quickshell.iconPath(n.appIcon, "dialog-information")
                                    return Quickshell.iconPath("dialog-information")
                                }
                            }
                            Column {
                                id: col
                                width: parent.width - 60
                                spacing: 2
                                Row {
                                    width: parent.width; spacing: 6
                                    Text {
                                        text: groupItem.latest.appName || "Notification"
                                        color: Theme.fg3
                                        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, parent.width - 30)
                                    }
                                    Rectangle {
                                        visible: groupItem.count > 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: cnt.implicitWidth + 10; height: 15; radius: Theme.r(7)
                                        color: Theme.accentFill
                                        Text { id: cnt; anchors.centerIn: parent; text: groupItem.count; color: Theme.accentOn; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.Bold }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: groupItem.latest.summary || ""
                                    color: Theme.fg1
                                    font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: groupItem.latest.body || ""
                                    color: Theme.fg2
                                    font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function (m) {
                                if (m.button === Qt.RightButton) { root.removeGroup(groupItem.modelData); return }
                                root.focusFrom(groupItem.latest)        // go to the window that notified
                                root.removeGroup(groupItem.modelData)   // dismiss the whole group
                            }
                        }
                    }
                }
            }
        }
    }
}
