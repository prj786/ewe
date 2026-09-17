import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Notifications — Quickshell IS the notification server now (replaces swaync).
// Live banners appear top-right (unless Do not disturb), GROUPED by app
// (design system: Notification).
//
//   banner    panelSm wide, surfaceRaised with a borderWidth1 borderSubtle
//             outline, the radiusRounded corner and the shadowFloat
//             elevation; spaceS of padding on top, spaceS + spaceXs on the
//             sides and the bottom
//   header    controlSm tall: the app icon on an iconMd radiusSlight tile,
//             the app's name in caption medium textSecondary, a dot and the
//             time in textMuted, and a close button that appears on hover
//   title     the body-strong style · body at most three lines in
//             textSecondary
//   media     an icon3xl (48) picture on the right, radiusPrimary
//   critical  a danger outline, and the title in danger behind a
//             triangle-alert glyph
//   grouped   the newest card over two spaceXs layers, with "N more from App"
//
// Clicking a banner focuses the window it came from (via its default action,
// falling back to focusing the app's window in Hyprland) and dismisses the
// group; right-clicking just dismisses it. The full list lives in Quick
// settings. The server is shared via Globals.server.
Scope {
    id: root

    property var popups: []
    property var groups: []   // [{ app, items:[n…], latest:n }] derived from popups
    // arrival times, keyed by notification id — the protocol carries none, and
    // the header's time needs one
    property var arrived: ({})
    property double now: Date.now()
    Timer { interval: 1000; repeat: true; running: root.groups.length > 0; onTriggered: root.now = Date.now() }
    // the Writing guide's relative times: "now", then "2 min ago"
    function ago(id) {
        var t = root.arrived[id]
        if (t === undefined) return "now"
        var mins = Math.floor((root.now - t) / 60000)
        return mins < 1 ? "now" : mins + " min ago"
    }

    function pushPopup(n) {
        var a = root.popups.slice(); a.push(n); root.popups = a
        root.arrived[n.id] = Date.now()
        root.rebuild()
    }
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
            // The sender may close it itself — KDE Connect does at the end of a
            // call, a download bar does when it finishes. Without this the
            // toast outlived the notification and sat there until its own
            // timer, or forever when it was replaced in place every second.
            n.closed.connect(function () { root.removePopup(n) })
            if (!Globals.dnd) Globals.playSound("message-new-instant")
            if (!Globals.dnd) root.pushPopup(n)
        }
    }

    // ── the grouped banner stack, top-right, below the bar ────────────────
    PanelWindow {
        visible: root.groups.length > 0 && !Globals.dnd
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors { top: true; right: true; left: true; bottom: true }

        // Only the banner column grabs pointer input; the rest is click-through.
        mask: Region { item: toastColumn }

        Column {
            id: toastColumn
            anchors.top: parent.top
            anchors.right: parent.right
            // the layer already sits below the bar's exclusive zone
            anchors.topMargin: Theme.windowGap
            anchors.rightMargin: Theme.windowGap
            spacing: Theme.windowGap
            // fade plus a slideOffset slide from the right edge, at durBase
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Theme.ease }
                NumberAnimation { property: "x"; from: Theme.reduceMotion ? 0 : Theme.slideOffset; to: 0
                                  duration: Theme.durBase; easing.type: Theme.ease }
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
                    readonly property bool critical: latest.urgency !== undefined
                                                     && String(latest.urgency).toLowerCase().indexOf("critical") >= 0
                    width: Theme.panelSm
                    height: card.height + (count > 1 ? Theme.spaceS + more.height + Theme.spaceXs : 0)

                    // expire the whole group together (latest notification's timeout)
                    Timer {
                        running: true
                        interval: groupItem.latest.expireTimeout > 0 ? groupItem.latest.expireTimeout : 5000
                        onTriggered: root.removeGroup(groupItem.modelData)
                    }

                    // the stack: two layers peeking out below the newest card
                    Rectangle {
                        visible: groupItem.count > 1
                        anchors.top: card.bottom; anchors.topMargin: -Theme.radiusRounded
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 2 * Theme.spaceS
                        height: Theme.spaceMd
                        radius: Theme.radiusRounded
                        color: Theme.surfaceRaised
                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                        z: -1
                    }
                    Rectangle {
                        visible: groupItem.count > 2
                        anchors.top: card.bottom; anchors.topMargin: -Theme.radiusRounded + Theme.spaceXs
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 2 * Theme.spaceMd
                        height: Theme.spaceMd
                        radius: Theme.radiusRounded
                        color: Theme.surfaceRaised
                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                        z: -2
                    }

                    Rectangle {
                        id: card
                        width: parent.width
                        height: col.implicitHeight + Theme.spaceS + Theme.spaceS + Theme.spaceXs
                        radius: Theme.radiusRounded
                        color: Theme.surfaceRaised
                        border.color: groupItem.critical ? Theme.danger : Theme.borderSubtle
                        border.width: Theme.borderWidth1
                        layer.enabled: true
                        layer.effect: Elevation {}

                        Column {
                            id: col
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                            anchors.topMargin: Theme.spaceS
                            spacing: Theme.spaceS

                            // ── header: app icon, name, time, count, close ──
                            Item {
                                width: parent.width
                                height: Theme.controlSm
                                Row {
                                    id: head
                                    anchors.left: parent.left
                                    anchors.right: closeBtn.left; anchors.rightMargin: Theme.spaceXs
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spaceXs
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.iconMd; height: Theme.iconMd
                                        radius: Theme.radiusSlight
                                        color: Theme.surfaceHover
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd
                                            mipmap: true
                                            source: {
                                                var n = groupItem.latest
                                                if (n.appIcon && n.appIcon != "") return Quickshell.iconPath(n.appIcon, "dialog-information")
                                                return Quickshell.iconPath("dialog-information")
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: groupItem.latest.appName || "Notification"
                                        color: Theme.textSecondary
                                        font.family: Theme.type.caption.family
                                        font.pixelSize: Theme.type.caption.size
                                        font.weight: Theme.fontWeightMedium
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, head.width - Theme.icon3xl)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "· " + root.ago(groupItem.latest.id)
                                        color: Theme.textMuted
                                        font.family: Theme.type.caption.family
                                        font.pixelSize: Theme.type.caption.size
                                    }
                                    Badge {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: groupItem.count > 1
                                        count: groupItem.count
                                    }
                                }
                                // the close button only shows while the pointer is over the banner
                                Rectangle {
                                    id: closeBtn
                                    anchors.right: parent.right; anchors.rightMargin: -Theme.spaceXs
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.controlSm; height: Theme.controlSm
                                    radius: Theme.radiusPrimary
                                    visible: cardMa.containsMouse || closeMa.containsMouse
                                    color: closeMa.containsMouse ? Theme.surfaceHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: Theme.icClose
                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                        color: Theme.textSecondary
                                    }
                                    MouseArea {
                                        id: closeMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.removeGroup(groupItem.modelData)
                                    }
                                }
                            }

                            // ── title, body and the optional picture ──
                            Row {
                                width: parent.width
                                spacing: Theme.spaceS + Theme.spaceXs
                                Column {
                                    id: content
                                    width: parent.width - (media.visible ? media.width + parent.spacing : 0)
                                    spacing: Theme.spaceXxs
                                    Row {
                                        width: parent.width
                                        spacing: Theme.spaceXs
                                        Text {
                                            visible: groupItem.critical
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Theme.icWarning
                                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                            color: Theme.danger
                                        }
                                        Text {
                                            width: parent.width - (groupItem.critical ? Theme.iconMd + parent.spacing : 0)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: groupItem.latest.summary || ""
                                            color: groupItem.critical ? Theme.danger : Theme.textPrimary
                                            font.family: Theme.type.bodyStrong.family
                                            font.pixelSize: Theme.type.bodyStrong.size
                                            font.weight: Theme.type.bodyStrong.weight
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        visible: text.length > 0
                                        text: groupItem.latest.body || ""
                                        color: Theme.textSecondary
                                        font.family: Theme.type.body.family
                                        font.pixelSize: Theme.type.body.size
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                    }
                                }
                                Rectangle {
                                    id: media
                                    visible: img.source != ""
                                    width: Theme.icon3xl; height: Theme.icon3xl
                                    radius: Theme.radiusPrimary
                                    color: Theme.surfaceHover
                                    clip: true
                                    Image {
                                        id: img
                                        anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl
                                        mipmap: true
                                        source: {
                                            var n = groupItem.latest
                                            return (n.image && n.image != "") ? n.image : ""
                                        }
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function (m) {
                                if (m.button === Qt.RightButton) { root.removeGroup(groupItem.modelData); return }
                                root.focusFrom(groupItem.latest)        // go to the window that notified
                                root.removeGroup(groupItem.modelData)   // dismiss the whole group
                            }
                        }
                    }

                    // "N more from App", below the stack
                    Text {
                        id: more
                        visible: groupItem.count > 1
                        anchors.top: card.bottom; anchors.topMargin: Theme.spaceS
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (groupItem.count - 1) + " more from " + (groupItem.latest.appName || "this app")
                        color: Theme.textMuted
                        font.family: Theme.type.caption.family
                        font.pixelSize: Theme.type.caption.size
                    }
                }
            }
        }
    }
}
