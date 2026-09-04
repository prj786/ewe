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
    spacing: 8

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
        var known = root.wifiSaved[ssid] === true
        if (sec && sec !== "" && !known && root.pwText === "") {
            root.pwTarget = (root.pwTarget === ssid) ? "" : ssid
            return
        }
        var cmd = (known && root.pwText === "")
            ? ["nmcli", "connection", "up", "id", ssid]
            : ["nmcli", "device", "wifi", "connect", ssid]
        if (root.pwText !== "") cmd = cmd.concat(["password", root.pwText])
        root.wifiPending = ssid
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
    Process {
        id: wifiSavedScan
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    var f = ls[i].split(":")
                    if (f.length >= 2 && f[f.length - 1] === "802-11-wireless")
                        m[f.slice(0, f.length - 1).join(":")] = true
                }
                root.wifiSaved = m
            }
        }
    }
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
            }
        }
    }
    Process {
        id: wifiConnProc
        stderr: StdioCollector { id: wifiConnErr }
        onExited: function (exitCode, exitStatus) {
            var failed = root.wifiPending
            root.wifiPending = ""
            root.rescan()
            if (exitCode !== 0) {
                var msg = (wifiConnErr.text || "").trim()
                if (/secrets|no key|password|802-1x|auth/i.test(msg)) root.pwTarget = failed
                root.lastError = "Joining " + failed + " failed" + (msg !== "" ? ": " + msg : " (nmcli exited with code " + exitCode + ")")
            }
        }
    }

    // ── status line ──
    Row {
        width: parent.width; spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.online ? Theme.icCheck : (root.wiredUp || root.wifiOn ? Theme.icWifi : Theme.icWifiOff)
            font.family: Theme.fontIcons; font.pixelSize: 14
            color: root.online ? Theme.success : Theme.fg3
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.online ? ("Connected" + (root.wiredUp ? " (Ethernet)" : (root.curSsid() !== "" ? " to " + root.curSsid() : "")))
                : (root.wiredUp ? "Ethernet link, but no internet yet…"
                : (root.wifiOn ? (root.curSsid() !== "" ? "Joined " + root.curSsid() + " — waiting for internet…" : "Not connected — pick a network below")
                : "Wi-Fi is off — turn it on to see networks"))
            color: root.online ? Theme.success : Theme.fg2
            font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
        }
    }
    Text {
        visible: !root.wifiOn
        text: "Turn Wi-Fi on"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["nmcli", "radio", "wifi", "on"]); rescanSoon.restart() } }
    }
    Timer { id: rescanSoon; interval: 1500; onTriggered: root.rescan() }

    // ── list ──
    Item {
        width: parent.width; height: 28; visible: root.wifiOn && root.wifiList.length === 0
        Row {
            anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Spinner { visible: wifiScan.running; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: wifiScan.running ? "Looking for networks…" : "No networks found."; color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
        }
    }
    Rectangle {
        width: parent.width
        visible: root.wifiOn && root.wifiList.length > 0
        height: visible ? Math.min(wifiOptCol.implicitHeight + 10, 232) : 0
        radius: Theme.r(7); color: Theme.bg3; border.color: Theme.stroke2; border.width: Theme.borderThin
        clip: true
        Flickable {
            anchors.fill: parent; anchors.margins: 5
            contentHeight: wifiOptCol.implicitHeight; clip: true
            Column {
                id: wifiOptCol
                width: parent.width
                Repeater {
                    model: root.wifiOn ? root.wifiList : []
                    delegate: Column {
                        required property var modelData
                        width: wifiOptCol.width
                        Item {
                            width: parent.width; height: 30
                            Rectangle { anchors.fill: parent; radius: Theme.r(6); color: wMa.containsMouse ? Theme.subtleHover : Theme.subtle }
                            Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.signal >= 66 ? Theme.icWifi : (modelData.signal >= 33 ? Theme.icWifiMed : Theme.icWifiLow); font.family: Theme.fontIcons; font.pixelSize: 13; color: modelData.active ? Theme.accent : Theme.fg3 }
                            Text { anchors.left: parent.left; anchors.leftMargin: 32; anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; text: modelData.ssid; color: modelData.active ? Theme.accent : Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                            Text { anchors.right: parent.right; anchors.rightMargin: modelData.active ? 26 : 8; anchors.verticalCenter: parent.verticalCenter; visible: modelData.sec !== ""; text: Theme.icLock; font.family: Theme.fontIcons; font.pixelSize: 10; color: Theme.fg3 }
                            Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: modelData.active && root.wifiPending !== modelData.ssid; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
                            Spinner { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: root.wifiPending === modelData.ssid; font.pixelSize: 12 }
                            MouseArea { id: wMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) }
                        }
                        Item {
                            width: parent.width; height: visible ? 36 : 0; visible: root.pwTarget === modelData.ssid
                            Rectangle {
                                anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 4; radius: Theme.r(7); color: Theme.bg3; border.color: Theme.accent; border.width: Theme.borderThin
                                TextInput {
                                    id: pwInput
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 84; verticalAlignment: TextInput.AlignVCenter
                                    echoMode: root.pwShow ? TextInput.Normal : TextInput.Password; color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                    onTextChanged: root.pwText = text
                                    Component.onCompleted: if (root.pwTarget === modelData.ssid) forceActiveFocus()
                                    onAccepted: root.connectWifi(modelData.ssid, modelData.sec)
                                    Keys.onEscapePressed: root.pwTarget = ""
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: pwInput.text.length === 0; text: "Password"; color: Theme.fg3; font: pwInput.font }
                                }
                                Text { anchors.right: parent.right; anchors.rightMargin: 46; anchors.verticalCenter: parent.verticalCenter; text: root.pwShow ? Theme.icEyeOff : Theme.icEye; font.family: Theme.fontIcons; font.pixelSize: 13; color: root.pwShow ? Theme.accent : Theme.fg3; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.pwShow = !root.pwShow } }
                                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "Join"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) } }
                            }
                        }
                    }
                }
            }
        }
    }
    Text {
        visible: root.lastError !== ""
        width: parent.width; wrapMode: Text.Wrap
        text: root.lastError; color: Theme.danger; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
    }
}
