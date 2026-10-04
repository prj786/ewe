import QtQuick
import qs

// ewe.vpn — the VPN page (quickPage.key "vpn": the rail entry, the tile's
// chevron, `qs ipc call quicksettings tab vpn`). Every NetworkManager VPN
// profile as a row; a click connects or disconnects. A profile without
// stored secrets opens its sign-in form right under the row: username,
// password, and for L2TP/IPsec the pre-shared key — kept in the profile on
// Connect, so the toggle works from then on.
Column {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})
    property bool panelOpen: false
    onPanelOpenChanged: Vpn.pageOpen = root.panelOpen
    spacing: Theme.spaceS

    QsPageHead { title: "VPN"; busy: Vpn.busyName !== "" }
    QsEmpty {
        visible: Vpn.list.length === 0
        ic: Theme.icVpn; title: "No VPN connections"
        desc: "Add a VPN connection, and it shows up here."
    }
    ListWell {
        flush: true
        visible: Vpn.list.length > 0
        Repeater {
            model: Vpn.list
            delegate: Column {
                id: vRow
                required property var modelData
                width: parent.width
                spacing: Theme.spaceS
                ListRow {
                    glyph: Theme.icVpn
                    glyphColor: vRow.modelData.active ? Theme.accentText : Theme.textSecondary
                    label: vRow.modelData.name
                    desc: Vpn.busyName === vRow.modelData.name ? "Connecting…" : vRow.modelData.active ? "Connected" : ""
                    active: vRow.modelData.active
                    check: vRow.modelData.active && Vpn.busyName !== vRow.modelData.name
                    busy: Vpn.busyName === vRow.modelData.name
                    onClicked: (Vpn.credTarget === vRow.modelData.name) ? Vpn.closeCredentials() : Vpn.toggle(vRow.modelData.name, !vRow.modelData.active)
                }
                // the sign-in form: username · password · (L2TP) pre-shared
                // key, stored in the profile on Connect, so the toggle works
                // from then on
                Column {
                    visible: Vpn.credTarget === vRow.modelData.name
                    width: parent.width
                    spacing: Theme.spaceS
                    leftPadding: Theme.spaceS; rightPadding: Theme.spaceS; bottomPadding: Theme.spaceS
                    readonly property real w: width - leftPadding - rightPadding
                    QsNote { width: parent.w; text: "Enter your sign-in details once. They’re kept in the connection." }
                    QsField {
                        width: parent.w
                        focused: vUser.activeFocus
                        QsFieldInput {
                            id: vUser
                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            placeholder: "Username"
                            text: Vpn.credUser
                            onTextChanged: Vpn.credUser = text
                            Component.onCompleted: if (Vpn.credTarget === vRow.modelData.name && text === "") forceActiveFocus()
                            Keys.onEscapePressed: Vpn.closeCredentials()
                        }
                    }
                    QsField {
                        width: parent.w
                        focused: vPass.activeFocus
                        error: Vpn.credError !== ""
                        QsFieldInput {
                            id: vPass
                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.controlSm + Theme.spaceXs
                            placeholder: "Password"
                            echoMode: Vpn.credShow ? TextInput.Normal : TextInput.Password
                            text: Vpn.credPass
                            onTextChanged: Vpn.credPass = text
                            Component.onCompleted: if (Vpn.credTarget === vRow.modelData.name && Vpn.credUser !== "") forceActiveFocus()
                            onAccepted: Vpn.credNeedsPsk ? vPsk.forceActiveFocus() : Vpn.saveCredentials()
                            Keys.onEscapePressed: Vpn.closeCredentials()
                        }
                        QsIconButton {
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceXxs
                            anchors.verticalCenter: parent.verticalCenter
                            ic: Vpn.credShow ? Theme.icEyeOff : Theme.icEye
                            selected: Vpn.credShow
                            onGo: Vpn.credShow = !Vpn.credShow
                        }
                    }
                    QsField {
                        visible: Vpn.credNeedsPsk
                        width: parent.w
                        focused: vPsk.activeFocus
                        QsFieldInput {
                            id: vPsk
                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            placeholder: "Pre-shared key (IPsec), if there is one"
                            echoMode: Vpn.credShow ? TextInput.Normal : TextInput.Password
                            text: Vpn.credPsk
                            onTextChanged: Vpn.credPsk = text
                            onAccepted: Vpn.saveCredentials()
                            Keys.onEscapePressed: Vpn.closeCredentials()
                        }
                    }
                    QsNote { visible: Vpn.credError !== ""; width: parent.w; tone: "danger"; text: Vpn.credError }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: parent.rightPadding
                        spacing: Theme.spaceS
                        QsButton { size: "md"; variant: "ghost"; label: "Cancel"; onGo: Vpn.closeCredentials() }
                        QsButton {
                            size: "md"; variant: "primary"
                            busy: Vpn.busyName === vRow.modelData.name
                            disabled: Vpn.busyName !== "" && Vpn.busyName !== vRow.modelData.name
                            label: Vpn.busyName === vRow.modelData.name ? "Connecting…" : "Connect"
                            onGo: Vpn.saveCredentials()
                        }
                    }
                }
            }
        }
    }
}
