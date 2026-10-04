import QtQuick
import qs

// ewe.phone — the Mobile page of Quick settings (quickPage.key "mobile", the
// key the shell's built-in page had, so `quicksettings tab mobile` keeps
// working). Was QuickSettings.qml's MOBILE column: pairing, the phone's
// notifications (reply, dismiss), and the SMS conversations with a thread
// view and compose. The host injects `panelOpen` — true while THIS page is
// on screen — which replaces the old `expanded === "mobile"` tests.
Column {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})
    property bool panelOpen: false

    // sub-state (was QuickSettings' mobileView / replyTarget)
    property string mobileView: "notifs"      // "notifs" | "msgs"
    property string replyTarget: ""           // notification id with the reply box open
    function fmtMsgTime(ms) {
        var d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        if (now.getTime() - ms < 6 * 86400000) return Qt.formatDateTime(d, "ddd")
        return Qt.formatDateTime(d, "d MMM")
    }

    spacing: Theme.spaceS

    // setTab("mobile") used to reset the view and refresh; the list on screen
    // marks everything seen
    onPanelOpenChanged: {
        if (!panelOpen) return
        root.mobileView = "notifs"
        Phone.refresh()
        Phone.markAllSeen()
    }
    Connections {
        target: Phone
        function onNotifsChanged() {
            if (root.panelOpen && root.mobileView === "notifs") Phone.markAllSeen()
        }
    }

    QsPageHead {
        title: Phone.connected ? Phone.device.name : "Mobile"
        note: Phone.connected ? "" : "KDE Connect"
        // the connected phone's battery
        Row {
            visible: Phone.connected && Phone.device.batteryCharge >= 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceXs
            rightPadding: Theme.spaceXs
            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                text: Phone.connected && Phone.device.isCharging ? Theme.icBolt : Theme.icBattFull
                font.pixelSize: Theme.iconSm
                color: Phone.connected && Phone.device.isCharging ? Theme.success : Theme.textSecondary
            }
            TextMono { anchors.verticalCenter: parent.verticalCenter; text: Phone.connected ? Phone.device.batteryCharge + "%" : "" }
        }
        QsIconButton { anchors.verticalCenter: parent.verticalCenter; ic: Theme.icRefresh; onGo: Phone.refresh() }
    }

    // — the bridge itself cannot run (python-dbus / python-gobject missing) —
    QsNote { visible: Phone.bridgeFailed; tone: "danger"; text: Phone.bridgeError }
    QsButton { visible: Phone.bridgeFailed; variant: "secondary"; label: "Retry"; onGo: Phone.retryBridge() }

    // — not installed —
    QsEmpty {
        visible: Phone.bridgeUp && !Phone.installed
        ic: Theme.icPhone; title: "KDE Connect isn’t installed"
        desc: "Install it with sudo pacman -S kdeconnect, then install the app on your phone. Both need the same Wi-Fi network."
    }
    // — installed, daemon down —
    Row {
        visible: Phone.installed && !Phone.daemonRunning
        width: parent.width; spacing: Theme.spaceS
        TextBody { anchors.verticalCenter: parent.verticalCenter; width: parent.width - kdStart.width - parent.spacing; text: "KDE Connect isn’t running."; color: Theme.textSecondary }
        QsButton { id: kdStart; anchors.verticalCenter: parent.verticalCenter; variant: "primary"; label: "Start"; onGo: Phone.refresh() }
    }

    // — incoming pair request —
    Column {
        width: parent.width; spacing: Theme.spaceS
        visible: Phone.device !== null && Phone.device.pairRequestedByPeer
        TextBody {
            width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone
            text: "“" + (Phone.device ? Phone.device.name : "") + "” wants to pair with this computer."
        }
        Row {
            anchors.right: parent.right
            spacing: Theme.spaceS
            QsButton { variant: "ghost"; label: "Reject"; onGo: Phone.cancelPair(Phone.device.id) }
            QsButton { variant: "primary"; label: "Accept"; onGo: Phone.acceptPair(Phone.device.id) }
        }
    }

    // — pairing in progress (we asked) —
    Row {
        visible: Phone.pairingId !== ""
        width: parent.width; spacing: Theme.spaceS
        Spinner { anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
        TextBody { anchors.verticalCenter: parent.verticalCenter; width: parent.width - Theme.iconSm - kpCancel.width - 2 * parent.spacing; text: "Pairing… Accept the request on your phone."; color: Theme.textSecondary }
        QsButton { id: kpCancel; anchors.verticalCenter: parent.verticalCenter; variant: "ghost"; label: "Cancel"; onGo: Phone.cancelPair(Phone.pairingId) }
    }
    QsNote { visible: Phone.pairError !== ""; tone: "danger"; text: Phone.pairError }

    // — no paired device: the phones in reach —
    Column {
        width: parent.width; spacing: Theme.spaceS
        visible: Phone.installed && Phone.daemonRunning
                 && (Phone.device === null || (!Phone.device.isPaired && !Phone.device.pairRequestedByPeer))
                 && Phone.pairingId === ""
        QsEmpty {
            visible: Phone.devices.length === 0
            ic: Theme.icPhone; title: "No phones found"
            desc: "Open KDE Connect on your phone. Both devices need the same network."
        }
        ListWell {
            flush: true
            visible: Phone.devices.length > 0
            Repeater {
                model: Phone.devices
                delegate: ListRow {
                    id: kpRow
                    required property var modelData
                    glyph: Theme.icPhone
                    label: modelData.name
                    desc: modelData.isReachable ? "" : "Offline"
                    disabled: !modelData.isReachable
                    onClicked: if (kpRow.modelData.isReachable) Phone.requestPair(kpRow.modelData.id)
                    QsButton {
                        visible: kpRow.modelData.isReachable
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "secondary"; label: "Pair"
                        onGo: Phone.requestPair(kpRow.modelData.id)
                    }
                }
            }
        }
    }

    // — paired but out of reach —
    QsNote {
        visible: Phone.device !== null && Phone.device.isPaired && !Phone.device.isReachable
        text: "“" + (Phone.device ? Phone.device.name : "") + "” is offline. Put it on the same network with KDE Connect open, then refresh."
    }

    // — connected: notifications ⇄ messages, and ring —
    Column {
        width: parent.width; spacing: Theme.spaceS
        visible: Phone.connected

        Row {
            width: parent.width; spacing: Theme.spaceS
            QsSegmented {
                width: parent.width - ringBtn.width - parent.spacing
                options: [{ label: "Notifications" + (Phone.unreadCount > 0 ? " · " + Phone.unreadCount : ""), value: "notifs" },
                          { label: "Messages", value: "msgs" }]
                value: root.mobileView
                onPicked: function (v) {
                    root.mobileView = v
                    if (v === "notifs") Phone.markAllSeen()
                    else Phone.loadConversations()
                }
            }
            // ring (find my phone)
            QsIconButton { id: ringBtn; anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBellRing; onGo: Phone.ring() }
        }

        // ── the phone's notifications ──
        Column {
            width: parent.width; spacing: Theme.spaceS; visible: root.mobileView === "notifs"
            QsEmpty { visible: Phone.notifs.length === 0; ic: Theme.icBell; title: "No notifications on the phone" }
            Flickable {
                width: parent.width
                visible: Phone.notifs.length > 0
                height: Math.min(kdcNotifCol.implicitHeight, Theme.panelSm - Theme.spaceXl - Theme.spaceLg)
                clip: true
                contentHeight: kdcNotifCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: kdcNotifCol
                    width: parent.width
                    Repeater {
                        model: Phone.notifs
                        delegate: Column {
                            id: knRow
                            required property var modelData
                            width: kdcNotifCol.width
                            Item {
                                width: parent.width
                                height: knBody.implicitHeight + 2 * Theme.spaceS
                                Rectangle {
                                    anchors.fill: parent; radius: Theme.radiusSecondary
                                    color: knMa.containsMouse ? Theme.surfaceHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                }
                                MouseArea { id: knMa; anchors.fill: parent; hoverEnabled: true }
                                Image {
                                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                    anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                    width: Theme.iconMd; height: Theme.iconMd
                                    visible: knRow.modelData.iconPath !== ""
                                    source: knRow.modelData.iconPath !== "" ? "file://" + knRow.modelData.iconPath : ""
                                    sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd; mipmap: true
                                }
                                Glyph {
                                    visible: knRow.modelData.iconPath === ""
                                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                    anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                    text: Theme.icPhone
                                }
                                Column {
                                    id: knBody
                                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.iconMd + Theme.spaceS + Theme.spaceXs
                                    anchors.right: knBtns.left; anchors.rightMargin: Theme.spaceXs
                                    anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                    spacing: Theme.spaceXxs
                                    TextStrong { width: parent.width; text: knRow.modelData.title || knRow.modelData.appName }
                                    Text {
                                        width: parent.width
                                        visible: text !== ""
                                        text: knRow.modelData.text || knRow.modelData.ticker
                                        color: Theme.textSecondary
                                        font.family: Theme.type.body.family
                                        font.pixelSize: Theme.type.body.size
                                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                    }
                                    TextCaption { text: knRow.modelData.appName }
                                }
                                Row {
                                    id: knBtns
                                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
                                    anchors.top: parent.top; anchors.topMargin: Theme.spaceXs
                                    spacing: Theme.spaceXxs
                                    // reply (only when the app allows it)
                                    QsIconButton {
                                        visible: knRow.modelData.replyId !== ""
                                        ic: Theme.icSend
                                        selected: root.replyTarget === knRow.modelData.id
                                        onGo: root.replyTarget = root.replyTarget === knRow.modelData.id ? "" : knRow.modelData.id
                                    }
                                    QsIconButton {
                                        visible: knRow.modelData.dismissable
                                        ic: Theme.icClose
                                        onGo: Phone.dismissNotif(knRow.modelData.id)
                                    }
                                }
                            }
                            // the inline reply
                            Row {
                                visible: root.replyTarget === knRow.modelData.id
                                width: parent.width; spacing: Theme.spaceS
                                leftPadding: Theme.spaceS; rightPadding: Theme.spaceS; bottomPadding: Theme.spaceS
                                QsField {
                                    width: parent.width - parent.leftPadding - parent.rightPadding - knSend.width - parent.spacing
                                    focused: knReply.activeFocus
                                    QsFieldInput {
                                        id: knReply
                                        anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                        placeholder: "Reply…"
                                        Component.onCompleted: if (root.replyTarget === knRow.modelData.id) forceActiveFocus()
                                        onAccepted: { if (text.trim() !== "") { Phone.replyNotif(knRow.modelData.replyId, text.trim()); root.replyTarget = "" } }
                                    }
                                }
                                QsButton {
                                    id: knSend
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: "md"; variant: "primary"; label: "Send"
                                    disabled: knReply.text.trim() === ""
                                    onGo: { Phone.replyNotif(knRow.modelData.replyId, knReply.text.trim()); root.replyTarget = "" }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── messages: the conversation list ⇄ a thread ──
        Column {
            width: parent.width; spacing: Theme.spaceS; visible: root.mobileView === "msgs"

            // conversation list
            Column {
                width: parent.width; spacing: Theme.spaceS; visible: Phone.openThread < 0
                Row {
                    visible: Phone.conversations.length === 0
                    spacing: Theme.spaceS
                    leftPadding: Theme.spaceS
                    Spinner { visible: Phone.convsRequested; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                    TextCaption { anchors.verticalCenter: parent.verticalCenter; text: Phone.convsRequested ? "Loading conversations from the phone…" : "No conversations yet" }
                }
                Flickable {
                    width: parent.width
                    visible: Phone.conversations.length > 0
                    height: Math.min(kdcConvCol.implicitHeight, Theme.panelSm - Theme.spaceXl - Theme.spaceMd)
                    clip: true
                    contentHeight: kdcConvCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: kdcConvCol
                        width: parent.width
                        Repeater {
                            model: Phone.conversations
                            delegate: QsMsgRow {
                                required property var modelData
                                title: modelData.display
                                line: modelData.body
                                time: root.fmtMsgTime(modelData.date)
                                unread: modelData.unread
                                onClicked: Phone.openConversation(modelData.threadId)
                            }
                        }
                    }
                }
            }

            // thread view
            Column {
                width: parent.width; spacing: Theme.spaceS; visible: Phone.openThread >= 0
                Row {
                    width: parent.width; spacing: Theme.spaceS
                    QsIconButton { anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBack; onGo: Phone.openThread = -1 }
                    TextStrong {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.controlMd - parent.spacing
                        text: {
                            for (var i = 0; i < Phone.conversations.length; i++)
                                if (Phone.conversations[i].threadId === Phone.openThread) return Phone.conversations[i].display
                            return "Conversation"
                        }
                    }
                }
                Rectangle {
                    width: parent.width; height: Theme.panelSm - Theme.spaceXl - Theme.spaceLg
                    radius: Theme.radiusRounded
                    color: Theme.surfaceSunken
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    Flickable {
                        id: kdcThreadFlick
                        anchors.fill: parent; anchors.margins: Theme.spaceS; clip: true
                        contentHeight: kdcThreadCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        // stick to the newest message
                        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                        // pull past the top → page older messages in
                        onAtYBeginningChanged: if (atYBeginning && contentHeight > height) Phone.loadOlder()
                        Column {
                            id: kdcThreadCol
                            width: parent.width; spacing: Theme.spaceXs
                            Repeater {
                                model: Phone.thread
                                delegate: Item {
                                    id: kmRow
                                    required property var modelData
                                    readonly property bool sent: modelData.type === 2
                                    width: kdcThreadCol.width
                                    height: kmBubble.height
                                    Rectangle {
                                        id: kmBubble
                                        anchors.right: kmRow.sent ? parent.right : undefined
                                        anchors.left: kmRow.sent ? undefined : parent.left
                                        width: Math.min(kmTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs), kmRow.width * 0.8)
                                        height: kmTxt.implicitHeight + 2 * Theme.spaceS
                                        radius: Theme.radiusRounded
                                        color: kmRow.sent ? Theme.accent : Theme.surfaceOverlay
                                        border.color: kmRow.sent ? "transparent" : Theme.borderSubtle
                                        border.width: Theme.borderWidth1
                                        opacity: kmRow.modelData.pending ? Theme.opacityApp : 1
                                        Text {
                                            id: kmTxt
                                            anchors.fill: parent
                                            anchors.topMargin: Theme.spaceS; anchors.bottomMargin: Theme.spaceS
                                            anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                                            text: kmRow.modelData.body !== "" ? kmRow.modelData.body
                                                : (kmRow.modelData.hasAttachments ? "Attachment. Open it on the phone." : "No text (MMS)")
                                            color: kmRow.sent ? Theme.onAccent : Theme.textPrimary
                                            font.family: Theme.type.body.family
                                            font.pixelSize: Theme.type.body.size
                                            font.italic: kmRow.modelData.body === ""
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // compose
                Row {
                    width: parent.width; spacing: Theme.spaceS
                    QsField {
                        width: parent.width - kdcSend.width - parent.spacing
                        focused: kdcCompose.activeFocus
                        QsFieldInput {
                            id: kdcCompose
                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            placeholder: "Message…"
                            onAccepted: { if (text.trim() !== "") { Phone.sendMessage(text.trim()); text = "" } }
                        }
                    }
                    QsButton {
                        id: kdcSend
                        anchors.verticalCenter: parent.verticalCenter
                        size: "md"; variant: "primary"; ic: Theme.icSend; label: "Send"
                        disabled: kdcCompose.text.trim() === ""
                        onGo: { Phone.sendMessage(kdcCompose.text.trim()); kdcCompose.text = "" }
                    }
                }
            }
        }
    }
}
