import QtQuick
import qs

// ewe.ssh — the SSH page (quickPage.key "ssh": the rail entry, the tile,
// `qs ipc call quicksettings tab ssh`). Hosts from ~/.ssh/config. Row click →
// a terminal ssh'd in; globe → SOCKS tunnel + the host's saved browse script
// (first click opens a paste-once editor); pencil edits the script; the stop
// mark stops a running tunnel.
Column {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})
    property bool panelOpen: false
    onPanelOpenChanged: Ssh.pageOpen = root.panelOpen
    spacing: Theme.spaceS

    QsPageHead { title: "SSH"; note: "~/.ssh/config" }
    Column {
        visible: Ssh.hosts.length === 0
        width: parent.width; spacing: Theme.spaceS
        QsEmpty { ic: Theme.icSsh; title: "No SSH hosts"; desc: "Add a host to ~/.ssh/config, like this:" }
        Rectangle {
            width: parent.width; height: sshSample.implicitHeight + 2 * Theme.spaceS
            radius: Theme.radiusPrimary
            color: Theme.surfaceSunken
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            Text {
                id: sshSample
                anchors.fill: parent; anchors.margins: Theme.spaceS
                text: "Host mypc\n    HostName 192.168.1.20\n    User you"
                color: Theme.textSecondary
                font.family: Theme.type.mono.family
                font.pixelSize: Theme.type.mono.size
            }
        }
    }
    ListWell {
        flush: true
        visible: Ssh.hosts.length > 0
        Repeater {
            model: Ssh.hosts
            delegate: Column {
                id: sshRow
                required property var modelData
                width: parent.width
                spacing: Theme.spaceXs
                ListRow {
                    glyph: Theme.icSsh
                    glyphColor: sshRow.modelData.tunnel ? Theme.accentText : Theme.textSecondary
                    label: sshRow.modelData.host
                    desc: sshRow.modelData.tunnel ? "Tunnel on" : ""
                    active: sshRow.modelData.tunnel
                    // the whole row (under the buttons) → a terminal
                    onClicked: Ssh.term(sshRow.modelData.host)
                    QsIconButton {
                        visible: sshRow.modelData.tunnel
                        anchors.verticalCenter: parent.verticalCenter
                        square: true; danger: true
                        onGo: Ssh.stopTunnel(sshRow.modelData.host)
                    }
                    QsIconButton {
                        visible: sshRow.modelData.script
                        anchors.verticalCenter: parent.verticalCenter
                        ic: Theme.icPencil
                        selected: Ssh.scriptTarget === sshRow.modelData.host
                        onGo: Ssh.editScript(sshRow.modelData.host)
                    }
                    // globe: run the host's browse script (or open the
                    // editor if none is saved yet)
                    QsIconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        ic: Theme.icWeb
                        onGo: Ssh.browse(sshRow.modelData.host, sshRow.modelData.script)
                    }
                }
                // the browse-script editor — paste once, kept in
                // ~/.config/quickshell/ssh-browse/<host>.sh
                Column {
                    width: parent.width; spacing: Theme.spaceS
                    bottomPadding: Theme.spaceS
                    visible: Ssh.scriptTarget === sshRow.modelData.host
                    onVisibleChanged: if (visible) { seEdit.text = Ssh.scriptText; seEdit.forceActiveFocus() }
                    Rectangle {
                        width: parent.width; height: 3 * Theme.control2xl
                        radius: Theme.radiusPrimary
                        color: Theme.surfaceSunken
                        border.color: seEdit.activeFocus ? Theme.focusRing : Theme.borderStrong
                        border.width: Theme.fieldBorderWidth
                        Flickable {
                            id: seFlick
                            anchors.fill: parent; anchors.margins: Theme.spaceS; clip: true
                            contentWidth: width; contentHeight: seEdit.implicitHeight
                            TextEdit {
                                id: seEdit
                                width: seFlick.width
                                textFormat: TextEdit.PlainText; wrapMode: TextEdit.WrapAnywhere
                                selectByMouse: true
                                color: Theme.textPrimary
                                selectionColor: Theme.accentSubtle
                                selectedTextColor: Theme.textPrimary
                                font.family: Theme.type.mono.family
                                font.pixelSize: Theme.type.mono.size
                                Keys.onEscapePressed: Ssh.scriptTarget = ""
                                // keep the cursor in view while typing or pasting
                                onCursorRectangleChanged: {
                                    if (cursorRectangle.y < seFlick.contentY) seFlick.contentY = cursorRectangle.y
                                    else if (cursorRectangle.y + cursorRectangle.height > seFlick.contentY + seFlick.height)
                                        seFlick.contentY = cursorRectangle.y + cursorRectangle.height - seFlick.height
                                }
                            }
                        }
                        QsNote {
                            visible: seEdit.text.length === 0
                            anchors.fill: parent; anchors.margins: Theme.spaceS
                            text: "Paste the shell script to run for “" + sshRow.modelData.host + "”, such as a browser that goes through the tunnel.\n\nIt runs with SSH_HOST and SOCKS_PORT set, once a SOCKS5 tunnel to the host is up on 127.0.0.1:$SOCKS_PORT (1080 by default; needs key or agent sign-in). Saved to ~/.config/quickshell/ssh-browse/."
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: Theme.spaceS
                        QsButton {
                            visible: sshRow.modelData.script
                            variant: "danger"; label: "Delete script"
                            onGo: Ssh.deleteScript(sshRow.modelData.host)
                        }
                        QsButton { variant: "ghost"; label: "Cancel"; onGo: Ssh.scriptTarget = "" }
                        QsButton {
                            variant: "primary"; label: "Save and run"
                            disabled: seEdit.text.trim().length === 0
                            onGo: Ssh.saveScript(sshRow.modelData.host, seEdit.text)
                        }
                    }
                }
            }
        }
    }
}
