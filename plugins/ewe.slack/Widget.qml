import QtQuick
import qs

// ewe.slack — the desktop widget: a solid card (or ewe's Glass one, setting
// `background`) with the unread Slack DMs, newest first. ewe owns where it
// sits (arrange mode, Super+Shift+W) and pads it inside its own card; the
// solid fill reaches back over that padding so the whole card is one colour.
Item {
    id: w
    property var settings: ({})
    readonly property bool solid: w.settings.background !== "glass"
    readonly property int maxRows: Math.max(1, Math.min(12, Number(w.settings.max_rows) || 6))

    implicitWidth: Theme.panelSm - 2 * Theme.spaceMd
    implicitHeight: body.implicitHeight

    Rectangle {
        visible: w.solid
        anchors.fill: parent
        anchors.leftMargin: -Theme.spaceMd; anchors.rightMargin: -Theme.spaceMd
        anchors.topMargin: -(Theme.spaceS + Theme.spaceXs); anchors.bottomMargin: -(Theme.spaceS + Theme.spaceXs)
        radius: Theme.radiusRounded
        color: Theme.surfaceBase
        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
    }

    Column {
        id: body
        width: parent.width
        spacing: Theme.spaceS

        Item {
            width: parent.width
            height: Theme.controlLg
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceS
                Glyph { anchors.verticalCenter: parent.verticalCenter; text: Theme.icMessage }
                TextStrong { anchors.verticalCenter: parent.verticalCenter; text: "Slack" }
                Badge { anchors.verticalCenter: parent.verticalCenter; visible: SlackInbox.unread > 0; count: SlackInbox.unread; max: 99 }
                Spinner { anchors.verticalCenter: parent.verticalCenter; visible: SlackInbox.busy; size: Theme.iconSm }
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceXxs
                QsIconButton { ic: Theme.icRefresh; onGo: SlackInbox.fetch() }
                QsIconButton { ic: Theme.icWeb; onGo: SlackInbox.openSlack() }
                QsIconButton { ic: Theme.icCog; onGo: SlackInbox.openSetup() }
            }
        }

        Column {
            visible: SlackInbox.state === "no-token" || SlackInbox.state === "auth"
            width: parent.width
            spacing: Theme.spaceS
            QsNote { text: SlackInbox.state === "auth" ? "Slack no longer accepts the saved token." : "Connect your Slack workspace to see unread messages here." }
            QsButton { label: "Connect Slack"; variant: "primary"; onGo: SlackInbox.openSetup() }
        }
        QsNote { visible: SlackInbox.error !== "" && SlackInbox.state !== "auth"; tone: "warning"; text: SlackInbox.error }
        QsNote { visible: SlackInbox.state === "offline"; text: "Offline. Showing the last check." }
        QsNote { visible: !SlackInbox.probed; text: "Checking Slack…" }
        TextCaption {
            visible: SlackInbox.probed && SlackInbox.available && SlackInbox.state === "" && SlackInbox.list.length === 0
            width: parent.width
            topPadding: Theme.spaceXs; bottomPadding: Theme.spaceXs
            horizontalAlignment: Text.AlignHCenter
            text: "All caught up — no unread messages."
        }

        Column {
            width: parent.width
            visible: SlackInbox.available && SlackInbox.list.length > 0
            Repeater {
                model: SlackInbox.list.slice(0, w.maxRows)
                delegate: SlackRow {
                    required property var modelData
                    conv: modelData
                    onClicked: SlackInbox.open(modelData)
                }
            }
            TextCaption {
                visible: SlackInbox.list.length > w.maxRows
                width: parent.width
                topPadding: Theme.spaceXs
                horizontalAlignment: Text.AlignHCenter
                text: "+" + (SlackInbox.list.length - w.maxRows) + " more"
            }
        }
    }
}
