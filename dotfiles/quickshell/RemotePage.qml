import QtQuick
import qs

// RemotePage — Control Centre → "remote" (RFC-009). Top: Share this
// computer (switch, the pairing code, who is connected now, who may connect).
// Below: Your computers — the other ewe computers on your account; pair
// once with the code the other one shows, then Terminal / Browse from it.
// State and actions: RemoteState (bin/ewe-remote).
Column {
    id: page
    spacing: Theme.spaceS

    function since(ts) {
        if (!ts) return ""
        return "since " + Qt.formatTime(new Date(ts * 1000), "hh:mm")
    }

    QsPageHead {
        title: "Share this computer"
        note: RemoteState.sharing ? "On" : "Off"
        hasSwitch: true
        on: RemoteState.sharing
        busy: RemoteState.busy === "share"
        switchDisabled: RemoteState.busy !== ""
        onToggled: RemoteState.setSharing(!RemoteState.sharing)
    }
    QsNote {
        visible: !RemoteState.sharing
        width: parent.width
        text: "Your other ewe computers can then open a terminal here, reach the files and browse the web from this computer. Each one pairs once, with a code shown here."
    }

    // ── the code ──
    Column {
        visible: RemoteState.sharing
        width: parent.width; spacing: Theme.spaceXs
        SectionTitle { text: "Pairing code" }
        Row {
            spacing: Theme.spaceS
            TextMono {
                anchors.verticalCenter: parent.verticalCenter
                text: RemoteState.codeDisplay
                color: Theme.textPrimary
                font.pixelSize: Theme.type.h2.size
            }
            QsIconButton {
                anchors.verticalCenter: parent.verticalCenter
                ic: Theme.icRefresh
                onGo: RemoteState.newCode()
            }
        }
        QsNote {
            width: parent.width
            text: "On your other computer: Control Centre → Sharing → " + (RemoteState.thisName || "this computer") + " → Pair, then type this code. It works once."
        }
    }

    // ── connected now ──
    Column {
        visible: RemoteState.sharing && RemoteState.people.length > 0
        width: parent.width; spacing: Theme.spaceXs
        SectionTitle { text: "Connected now" }
        ListWell {
            flush: true
            Repeater {
                model: RemoteState.people
                delegate: ListRow {
                    required property var modelData
                    glyph: Theme.icComputer
                    glyphColor: Theme.accentText
                    label: modelData.name || "Unknown"
                    desc: (modelData.from || "") + (modelData.since ? " · " + page.since(modelData.since) : "")
                    active: true
                    QsButton {
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Disconnect"; variant: "ghost"
                        onGo: RemoteState.disconnect(modelData.id)
                    }
                }
            }
        }
    }

    // ── may connect ──
    Column {
        visible: RemoteState.allowed.length > 0
        width: parent.width; spacing: Theme.spaceXs
        SectionTitle { text: "Can control this computer" }
        ListWell {
            flush: true
            Repeater {
                model: RemoteState.allowed
                delegate: ListRow {
                    required property var modelData
                    glyph: Theme.icComputer
                    label: modelData.name || modelData.id
                    desc: modelData.since ? "Paired " + modelData.since : ""
                    QsButton {
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Remove"; variant: "danger"
                        onGo: RemoteState.revoke(modelData.id)
                    }
                }
            }
        }
    }

    // ── your computers ──
    SectionTitle { text: "Your computers" }
    QsEmpty {
        visible: RemoteState.computers.length === 0
        ic: Theme.icComputer
        title: "No other computers yet"
        desc: RemoteState.registry === "not-signed-in"
              ? "Sign in to your ewe account, then turn on Share this computer on another ewe computer."
              : "Turn on Share this computer on another ewe computer signed in to your account."
    }
    ListWell {
        flush: true
        visible: RemoteState.computers.length > 0
        Repeater {
            model: RemoteState.computers
            delegate: Column {
                id: cRow
                required property var modelData
                readonly property bool reachable: modelData.online !== false
                width: parent.width
                spacing: Theme.spaceXs
                ListRow {
                    glyph: Theme.icComputer
                    glyphColor: cRow.modelData.tunnel ? Theme.accentText : Theme.textSecondary
                    label: cRow.modelData.name || cRow.modelData.id
                    desc: cRow.modelData.paired
                          ? (cRow.modelData.sharing === false ? "Paired · not shared now"
                             : cRow.modelData.online === false ? "Paired · offline" : "Paired")
                          : (cRow.modelData.sharing ? (cRow.reachable ? "Shared · pair with its code" : "Shared · offline")
                             : "Not shared")
                    active: !!cRow.modelData.tunnel
                    disabled: !cRow.modelData.paired && !cRow.modelData.sharing
                    onClicked: if (cRow.modelData.paired) RemoteState.terminal(cRow.modelData.id)
                    // paired: a terminal there, the web from there
                    QsIconButton {
                        visible: cRow.modelData.paired
                        anchors.verticalCenter: parent.verticalCenter
                        ic: Theme.icSsh
                        onGo: RemoteState.terminal(cRow.modelData.id)
                    }
                    QsIconButton {
                        visible: cRow.modelData.paired
                        anchors.verticalCenter: parent.verticalCenter
                        ic: Theme.icWeb
                        onGo: RemoteState.browse(cRow.modelData.id)
                    }
                    QsButton {
                        visible: !cRow.modelData.paired && cRow.modelData.sharing === true
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Pair"; variant: "secondary"
                        onGo: RemoteState.openPair(cRow.modelData.id)
                    }
                }
                // the code field — typed once, the other computer needs nobody at it
                Column {
                    visible: RemoteState.pairTarget === cRow.modelData.id
                    width: parent.width; spacing: Theme.spaceS
                    bottomPadding: Theme.spaceS
                    onVisibleChanged: if (visible) { codeIn.text = ""; codeIn.forceActiveFocus() }
                    Row {
                        width: parent.width; spacing: Theme.spaceS
                        QsField {
                            width: parent.width - pairBtn.width - Theme.spaceS
                            focused: codeIn.activeFocus
                            error: RemoteState.pairError !== ""
                            QsFieldInput {
                                id: codeIn
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                placeholder: "8-digit code from " + (cRow.modelData.name || "that computer")
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: RegularExpressionValidator { regularExpression: /[0-9 -]{0,10}/ }
                                onAccepted: if (codeIn.text.replace(/\D/g, "").length === 8) RemoteState.pair(cRow.modelData.id, codeIn.text)
                                Keys.onEscapePressed: RemoteState.pairTarget = ""
                            }
                        }
                        QsButton {
                            id: pairBtn
                            label: "Pair"; variant: "primary"
                            busy: RemoteState.busy === "pair"
                            disabled: codeIn.text.replace(/\D/g, "").length !== 8 || RemoteState.busy !== ""
                            onGo: RemoteState.pair(cRow.modelData.id, codeIn.text)
                        }
                    }
                    QsNote {
                        visible: RemoteState.pairError !== ""
                        width: parent.width
                        tone: "danger"
                        text: RemoteState.pairError
                    }
                }
            }
        }
    }
    // Between networks (home ↔ work) both computers need Tailscale — set it
    // up right here (NetState owns it: ewe-tailscale, one admin password)
    Column {
        visible: NetState.tsPhase !== "on"
        width: parent.width; spacing: Theme.spaceS
        QsNote {
            width: parent.width
            text: !NetState.tsInstalled
                  ? "Only computers on this network can be reached. To reach one at home or at work, both need Tailscale."
                  : "Tailscale: " + NetState.tsText + " — without it, only computers on this network can be reached. Both computers need it."
        }
        QsNote {
            visible: NetState.tsError !== ""
            width: parent.width
            tone: "danger"
            text: NetState.tsError
        }
        QsButton {
            visible: NetState.tsInstalled && NetState.tsPhase !== "starting"
            label: NetState.tsPhase === "setup" ? "Set up Tailscale"
                 : NetState.tsPhase === "signin" ? "Sign in to Tailscale"
                 : "Turn on Tailscale"
            variant: "secondary"
            busy: NetState.tsBusy !== ""
            disabled: NetState.tsBusy !== ""
            onGo: NetState.tsRun(NetState.tsPhase === "setup" ? "setup" : "up")
        }
    }
}
