import QtQuick
import qs

// ewe.mail — the Inbox page of Quick settings (quickPage.key "mail", the key
// the shell's built-in page had, so `quicksettings tab mail` keeps working).
// Was QuickSettings.qml's MAIL column: the head with the unread count, the
// notification toggle, refresh and "Open mail/Gmail", then the latest ten
// messages as compact two-line rows — no inner scrolling.
Column {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})
    property bool panelOpen: false

    function fmtMsgTime(ms) {
        var d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        if (now.getTime() - ms < 6 * 86400000) return Qt.formatDateTime(d, "ddd")
        return Qt.formatDateTime(d, "d MMM")
    }

    spacing: Theme.spaceS
    // setTab("mail") used to fetch when an account is there
    onPanelOpenChanged: if (panelOpen && Inbox.available) Inbox.fetch()

    QsPageHead {
        title: Inbox.available ? "Inbox" : "Mail"
        note: Inbox.available && Inbox.unread > 0 ? Inbox.unread + " unread" : ""
        // new-mail notifications on or off
        QsIconButton { visible: Inbox.available; anchors.verticalCenter: parent.verticalCenter; ic: Theme.icBellRing; selected: Inbox.notify; onGo: Inbox.setNotify(!Inbox.notify) }
        QsIconButton { visible: Inbox.available; anchors.verticalCenter: parent.verticalCenter; ic: Theme.icRefresh; onGo: Inbox.fetch() }
        QsButton { anchors.verticalCenter: parent.verticalCenter; label: Inbox.inboxLabel; onGo: Inbox.openInbox() }
    }
    QsNote { visible: !Inbox.available; text: Inbox.hint }
    QsNote { visible: Inbox.available && Inbox.error !== ""; tone: "warning"; text: Inbox.error }
    QsButton { visible: Inbox.needsReconnect; variant: "primary"; label: "Reconnect Google"; onGo: Inbox.reconnect() }
    QsNote { visible: Inbox.available && Inbox.state === "offline"; text: "Offline. Showing the last check." }
    QsEmpty {
        visible: Inbox.available && Inbox.state === "" && Inbox.list.length === 0
        ic: Theme.icMail; title: "No mail"; desc: "Your inbox is empty."
    }
    // the latest 10, compact two-line rows — no inner scrolling
    ListWell {
        flush: true
        visible: Inbox.available && Inbox.list.length > 0
        Repeater {
            model: Inbox.list.slice(0, 10)
            delegate: QsMsgRow {
                required property var modelData
                title: modelData.from
                line: modelData.subject
                time: root.fmtMsgTime(modelData.date)
                unread: modelData.unread
                onClicked: Inbox.open(modelData.id)
            }
        }
    }
}
