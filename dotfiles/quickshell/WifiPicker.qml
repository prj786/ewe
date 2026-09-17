import QtQuick
import Quickshell
import Quickshell.Io

// WifiPicker — a self-contained "get me online" widget: wired state, the
// Wi-Fi list (signal + lock glyph), an inline password field and Join,
// through nmcli exactly like the Control Center's Wi-Fi card. Born for the
// first-run Welcome flow (0.9.16-2 hotfix: on the first bare-metal install
// the Welcome overlay sat ABOVE the Control Center, so a machine with no
// Ethernet could not join Wi-Fi to reach the Google step at all). Kept
// separate from QuickSettings on purpose — a hotfix must not refactor the
// panel; the two share the same nmcli contract.
//
// Design system: Wi-Fi picker.
//
//   status  an iconMd glyph and a body-strong line: "Connected to <network>"
//           in success, or the offline wording in textSecondary behind
//           wifi-off
//   box     surfaceSunken inside a borderWidth1 borderSubtle outline on the
//           radiusPrimary corner, spaceXs of padding, scrolling after 8 rows
//   row     controlMd on the radiusSecondary corner: the signal glyph, the
//           name, a lock for secured networks, and a tick (connected) or a
//           Spinner (joining); the connected row is accentText at semibold
//   join    the row being joined becomes a borderless field with a show/hide
//           eye and a small primary Join, inside a focusRing outline
//   error   the caption size in danger behind a warning glyph
//
//   active   scanning/polling only while true (the host step is on screen)
//   online   true once NetworkManager reports full connectivity (or, with
//            connectivity checks disabled, the sign-in host answers)
Column {
    id: root
    property bool active: false
    property bool online: false
    property string connectivity: ""     // raw nmcli word: full · limited · portal · none · unknown
    property bool wiredUp: false
    property bool wifiOn: false
    property var wifiList: []
    property var wifiSaved: ({})
    property string wifiPending: ""
    property string pwTarget: ""
    property string pwText: ""
    property bool pwShow: false
    property string lastError: ""
    spacing: Theme.spaceS

    function curSsid() {
        for (var i = 0; i < root.wifiList.length; i++) if (root.wifiList[i].active) return root.wifiList[i].ssid
        return ""
    }
    function rescan() {
        wiredState.running = true; wifiState.running = true; wifiSavedScan.running = true
        wifiScan.running = true; connProc.running = true
    }
    function connectWifi(ssid, sec) {
        if (root.curSsid() === ssid && root.pwTarget !== ssid) return
        // same rules as Quick Settings: a saved profile (matched by SSID) joins
        // without a prompt; a fresh key goes into the existing profile
        var saved = root.wifiSaved[ssid] || null
        var needsKey = sec && sec !== "" && (!saved || saved.psk === "agent")
        if (needsKey && root.pwText === "") {
            root.pwTarget = (root.pwTarget === ssid) ? "" : ssid
            return
        }
        var cmd
        if (saved && root.pwText === "")
            cmd = ["nmcli", "connection", "up", "id", saved.name]
        else if (saved)
            cmd = ["sh", "-c", 'nmcli connection modify "$1" 802-11-wireless-security.psk "$2" 802-11-wireless-security.psk-flags 0 && exec nmcli connection up id "$1"', "_", saved.name, root.pwText]
        else {
            cmd = ["nmcli", "device", "wifi", "connect", ssid]
            if (root.pwText !== "") cmd = cmd.concat(["password", root.pwText])
        }
        root.wifiPending = ssid
        root.wifiConfirm = ""
        root.lastError = ""
        wifiConnProc.command = cmd
        wifiConnProc.running = true
        root.pwTarget = ""; root.pwText = ""
    }

    onActiveChanged: if (active) root.rescan()
    Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.rescan() }

    // connectivity: NetworkManager's own verdict, and — because Arch ships
    // with connectivity checking OFF (nmcli then says "unknown"/"limited"
    // even on a working link) — a direct HEAD to the host sign-in needs
    Process {
        id: connProc
        command: ["sh", "-c",
            's=$(nmcli -t networking connectivity 2>/dev/null); ' +
            'if [ "$s" = full ]; then echo online; ' +
            'elif curl -fsI --max-time 4 https://accounts.google.com >/dev/null 2>&1; then echo online; ' +
            'else echo "${s:-none}"; fi']
        stdout: StdioCollector {
            onStreamFinished: {
                var s = this.text.trim()
                root.connectivity = s
                root.online = (s === "online")
            }
        }
    }
    Process { id: wifiState; command: ["nmcli", "-t", "-f", "WIFI", "radio"]; stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" } }
    Process { id: wiredState; command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$1==\"ethernet\" && $2==\"connected\"{print \"yes\"; exit}'"]; stdout: StdioCollector { onStreamFinished: root.wiredUp = this.text.trim() === "yes" } }
    // saved profiles by SSID — {ssid: {name, psk}}, see scripts/wifi-profiles.sh
    readonly property string wifiProfilesScript: Qt.resolvedUrl("scripts/wifi-profiles.sh").toString().replace(/^file:\/\//, "")
    Process {
        id: wifiSavedScan
        command: ["bash", root.wifiProfilesScript]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    var f = ls[i].split("\t")
                    if (f.length >= 3 && f[0] !== "") m[f[0]] = { name: f[1], psk: f[2] }
                }
                root.wifiSaved = m
            }
        }
    }
    // the network we just joined, until a list read shows it IN-USE
    property string wifiConfirm: ""
    Timer { id: wifiConfirmTimer; interval: 4000; onTriggered: { root.wifiConfirm = ""; root.wifiPending = "" } }
    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), seen = {}, arr = []
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var p = lines[i].split(":")
                    var ssid = p.slice(3).join(":")
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    arr.push({ ssid: ssid, signal: parseInt(p[1]) || 0, sec: p[2] || "", active: p[0] === "*" })
                }
                arr.sort(function (a, b) { return (b.active - a.active) || (b.signal - a.signal) })
                root.wifiList = arr
                if (root.wifiConfirm !== "" && root.curSsid() === root.wifiConfirm) {
                    root.wifiConfirm = ""; root.wifiPending = ""; wifiConfirmTimer.stop()
                }
            }
        }
    }
    Process {
        id: wifiConnProc
        stderr: StdioCollector { id: wifiConnErr }
        onExited: function (exitCode, exitStatus) {
            var failed = root.wifiPending
            if (exitCode === 0) {
                // keep the spinner until the list shows us on the network (≤ 4 s)
                root.wifiConfirm = failed
                wifiConfirmTimer.restart()
                root.rescan()
                return
            }
            root.wifiPending = ""
            root.rescan()
            if (exitCode !== 0) {
                var msg = (wifiConnErr.text || "").trim()
                if (/secrets|no key|password|802-1x|auth/i.test(msg)) root.pwTarget = failed
                root.lastError = "Couldn\u2019t join " + failed
                    + (msg !== "" ? ": " + msg.charAt(0).toLowerCase() + msg.slice(1) : ".")
            }
        }
    }

    // ── status line ──
    Row {
        width: parent.width; spacing: Theme.spaceS
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.online ? Theme.icCheck : (root.wiredUp || root.wifiOn ? Theme.icWifi : Theme.icWifiOff)
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
            color: root.online ? Theme.success : Theme.textSecondary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.iconMd - parent.spacing
            text: root.online ? (root.wiredUp ? "Connected over Ethernet"
                                : root.curSsid() !== "" ? "Connected to " + root.curSsid() : "Connected")
                : (root.wiredUp ? "Ethernet is plugged in. Waiting for the internet…"
                : (root.wifiOn ? (root.curSsid() !== ""
                                  ? "Joined " + root.curSsid() + ". Waiting for the internet…"
                                  : "Not connected. Pick a network.")
                : "Wi-Fi is off"))
            color: root.online ? Theme.success : Theme.textSecondary
            font.family: Theme.type.bodyStrong.family
            font.pixelSize: Theme.type.bodyStrong.size
            font.weight: Theme.fontWeightSemibold
            elide: Text.ElideRight
        }
    }
    Text {
        visible: !root.wifiOn
        text: "Turn on Wi-Fi"
        color: Theme.accentText
        font.family: Theme.type.body.family
        font.pixelSize: Theme.type.body.size
        font.weight: Theme.fontWeightSemibold
        MouseArea {
            anchors.fill: parent; anchors.margins: -Theme.spaceXs
            cursorShape: Qt.PointingHandCursor
            onClicked: { Quickshell.execDetached(["nmcli", "radio", "wifi", "on"]); rescanSoon.restart() }
        }
    }
    Timer { id: rescanSoon; interval: 1500; onTriggered: root.rescan() }

    // ── the list ──
    Item {
        width: parent.width; height: Theme.controlLg
        visible: root.wifiOn && root.wifiList.length === 0
        Row {
            anchors.centerIn: parent
            spacing: Theme.spaceS
            Spinner { visible: wifiScan.running; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconMd }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: wifiScan.running ? "Looking for networks…" : "No networks found."
                color: Theme.textSecondary
                font.family: Theme.type.label.family
                font.pixelSize: Theme.fontSizeS
            }
        }
    }
    Rectangle {
        width: parent.width
        visible: root.wifiOn && root.wifiList.length > 0
        // the card's eight rows, then it scrolls
        height: visible ? Math.min(wifiOptCol.implicitHeight + 2 * Theme.spaceXs,
                                   8 * Theme.controlMd + 2 * Theme.spaceXs) : 0
        radius: Theme.radiusPrimary
        color: Theme.surfaceSunken
        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
        clip: true
        Flickable {
            anchors.fill: parent; anchors.margins: Theme.spaceXs + parent.border.width
            contentHeight: wifiOptCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: wifiOptCol
                width: parent.width
                spacing: Theme.spaceXxs
                Repeater {
                    model: root.wifiOn ? root.wifiList : []
                    delegate: Column {
                        required property var modelData
                        width: wifiOptCol.width
                        spacing: Theme.spaceXxs
                        Item {
                            width: parent.width; height: Theme.controlMd
                            visible: root.pwTarget !== modelData.ssid
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusSecondary
                                color: wMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                            }
                            Text {
                                id: sig
                                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.signal >= 66 ? Theme.icWifi
                                    : modelData.signal >= 33 ? Theme.icWifiMed : Theme.icWifiLow
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                color: modelData.active ? Theme.accentText : Theme.textSecondary
                            }
                            Text {
                                anchors.left: sig.right; anchors.leftMargin: Theme.spaceS
                                anchors.right: tail.left; anchors.rightMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.ssid
                                color: modelData.active ? Theme.accentText : Theme.textPrimary
                                font.family: Theme.type.body.family
                                font.pixelSize: Theme.type.body.size
                                font.weight: modelData.active ? Theme.fontWeightSemibold : Theme.type.body.weight
                                elide: Text.ElideRight
                            }
                            Row {
                                id: tail
                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceS
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.sec !== ""
                                    text: Theme.icLock
                                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                    color: Theme.textMuted
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.active && root.wifiPending !== modelData.ssid
                                    text: Theme.icCheck
                                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                    color: Theme.accentText
                                }
                                Spinner {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.wifiPending === modelData.ssid
                                    size: Theme.iconMd
                                }
                            }
                            MouseArea {
                                id: wMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectWifi(modelData.ssid, modelData.sec)
                            }
                        }
                        // the password row REPLACES the row being joined
                        Rectangle {
                            width: parent.width
                            height: visible ? Theme.controlMd : 0
                            visible: root.pwTarget === modelData.ssid
                            radius: Theme.radiusSecondary
                            color: Theme.surfaceBase
                            border.color: Theme.focusRing; border.width: Theme.borderWidth1
                            TextInput {
                                id: pwInput
                                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                anchors.right: eye.left; anchors.rightMargin: Theme.spaceXs
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: root.pwShow ? TextInput.Normal : TextInput.Password
                                color: Theme.textPrimary
                                font.family: Theme.type.body.family
                                font.pixelSize: Theme.type.body.size
                                onTextChanged: root.pwText = text
                                Component.onCompleted: if (root.pwTarget === modelData.ssid) forceActiveFocus()
                                onAccepted: root.connectWifi(modelData.ssid, modelData.sec)
                                Keys.onEscapePressed: root.pwTarget = ""
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pwInput.text.length === 0
                                    text: "Password"; color: Theme.textMuted; font: pwInput.font
                                }
                            }
                            Text {
                                id: eye
                                anchors.right: joinBtn.left; anchors.rightMargin: Theme.spaceXs
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.pwShow ? Theme.icEyeOff : Theme.icEye
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                color: root.pwShow ? Theme.accentText : Theme.textMuted
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -Theme.spaceXs
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pwShow = !root.pwShow
                                }
                            }
                            Rectangle {
                                id: joinBtn
                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceXxs
                                anchors.verticalCenter: parent.verticalCenter
                                width: joinTxt.implicitWidth + 2 * Theme.spaceS
                                height: Theme.controlSm
                                radius: Theme.radiusSecondary
                                color: joinMa.pressed ? Theme.accentPressed
                                     : joinMa.containsMouse ? Theme.accentHover : Theme.accent
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Text {
                                    id: joinTxt
                                    anchors.centerIn: parent; text: "Join"
                                    color: Theme.onAccent
                                    font.family: Theme.type.label.family
                                    font.pixelSize: Theme.type.label.size
                                    font.weight: Theme.fontWeightSemibold
                                }
                                MouseArea {
                                    id: joinMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.connectWifi(modelData.ssid, modelData.sec)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Row {
        visible: root.lastError !== ""
        width: parent.width; spacing: Theme.spaceXs
        Text {
            text: Theme.icWarning
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
            color: Theme.danger
        }
        Text {
            width: parent.width - Theme.iconSm - parent.spacing
            wrapMode: Text.Wrap
            text: root.lastError; color: Theme.danger
            font.family: Theme.type.label.family
            font.pixelSize: Theme.fontSizeS
        }
    }
}
