import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// hypr-shell greeter — a Quickshell/QML login that matches the shell theme.
// Launched by greetd as:  cage -s -- qs -c hyprshell-greeter  (see phase 30).
// Layout mirrors the agreed mockup: centred avatar + username + password,
// clock bottom-left, session picker bottom-right, no power buttons.
//
// Quickshell's Greetd singleton speaks the greetd protocol for us:
//   createSession(user) → authMessage(...) → respond(pw) → readyToLaunch() → launch(argv)
FloatingWindow {
    id: win
    title: "hypr-shell"
    implicitWidth: 1920
    implicitHeight: 1080
    color: pal.bg

    // ── palette (mirrors Theme.qml defaults; greeter runs as the system
    //    `greeter` user so it can't read the user's accent — use the default). ──
    QtObject {
        id: pal
        readonly property color bg: "#0e0e10"
        readonly property color fg: "#e6e6e6"
        readonly property color fgDim: "#8a8a8e"
        readonly property color field: "#1c1c1f"
        readonly property color stroke: "#3a3a3e"
        readonly property color accent: "#0a84ff"
        readonly property color danger: "#ff453a"
        readonly property string fontText: "Inter"
        readonly property string fontMono: "JetBrainsMono Nerd Font"
    }

    // cage shows the greeter as ONE surface stretched across every connected
    // output, so anchoring to the window centres in the union of all screens
    // (way off-centre on each physical panel). Pin the UI to a single screen's
    // region instead — the built-in panel when present, else the first.
    readonly property var scr: {
        var ss = Quickshell.screens
        for (var i = 0; i < ss.length; i++)
            if (/^(eDP|LVDS|DSI)/i.test(ss[i].name)) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    // cage leaves outputs at scale 1, so HiDPI laptop panels render the UI at
    // half size — treat tall panels as ~2x and transform-scale (Qt's distance-
    // field text stays crisp under scale).
    readonly property real ui: stage.height >= 1600 ? stage.height / 900 : 1

    property string userName: ""
    property string userReal: ""
    property string clockText: ""
    property string dateText: ""
    property string statusMsg: ""
    property bool   failed: false
    property bool   busy: false
    property var    sessions: []
    property int    sessionIdx: 0
    property bool   sessionMenuOpen: false
    property bool   sessionStarted: false

    function beginAuth() {
        if (win.userName === "" || !Greetd.available || win.sessionStarted) return
        win.failed = false; win.statusMsg = ""; win.busy = false
        win.sessionStarted = true
        Greetd.createSession(win.userName)
    }
    function submit() {
        if (win.busy || pw.text.length === 0) return
        win.busy = true; win.statusMsg = ""
        Greetd.respond(pw.text)
    }
    function doLaunch() {
        var s = win.sessions[win.sessionIdx]
        var argv = (s && s.exec) ? s.exec.split(/\s+/) : ["sh"]
        Greetd.launch(argv)
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            win.busy = false
            if (error)
                win.statusMsg = message
            if (responseRequired) { pw.text = ""; pw.forceActiveFocus() }
            // non-response (info) messages: greetd advances the PAM flow itself.
        }
        function onReadyToLaunch() { win.doLaunch() }
        function onAuthFailure(message) {
            win.busy = false; win.failed = true; win.sessionStarted = false
            win.statusMsg = (message && message.length) ? message : "Authentication failed"
            pw.text = ""
            retry.restart()   // greetd ended the session; restart so the user can retry
        }
        function onError(e) { win.busy = false; win.failed = true; win.sessionStarted = false; win.statusMsg = e; retry.restart() }
        function onLaunched() { /* session started — qs exits */ }
    }
    Timer { id: retry; interval: 500; onTriggered: win.beginAuth() }
    // start auth once both the user and the greetd socket are ready
    Connections { target: Greetd; function onAvailableChanged() { if (Greetd.available) win.beginAuth() } }

    // ── who to log in: first normal user (uid ≥ 1000) ──
    Process {
        id: userProc; running: true
        command: ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1\"\\t\"$5; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim().split("\t")
                win.userName = t[0] || ""
                var real = (t[1] || "").split(",")[0]
                win.userReal = (real && real.length) ? real : win.userName
                win.beginAuth()
            }
        }
    }
    // ── available sessions (the dropdown) ──
    Process {
        id: sessProc; running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop /usr/local/share/wayland-sessions/*.desktop; do [ -r \"$f\" ] || continue; n=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); e=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-); [ -n \"$e\" ] && printf '%s\\t%s\\n' \"$n\" \"$e\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var arr = [], seen = {}, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    if (!ls[i]) continue
                    var p = ls[i].split("\t")
                    if (!p[1] || seen[p[1]]) continue
                    seen[p[1]] = 1
                    arr.push({ name: p[0] || p[1], exec: p[1] })
                }
                win.sessions = arr
                for (var j = 0; j < arr.length; j++)
                    if (/hyprland \(de\)/i.test(arr[j].name)) { win.sessionIdx = j; break }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { var d = new Date(); win.clockText = Qt.formatDateTime(d, "HH:mm"); win.dateText = Qt.formatDateTime(d, "dddd, d MMMM") } }

    // ══════════════════════ UI ══════════════════════
    Item {
        anchors.fill: parent

        // close the session menu on an outside click
        MouseArea { anchors.fill: parent; enabled: win.sessionMenuOpen; onClicked: win.sessionMenuOpen = false }

        // everything lives inside the chosen screen's region, not the window
        Item {
            id: stage
            x: win.scr ? win.scr.x : 0
            y: win.scr ? win.scr.y : 0
            width: win.scr ? win.scr.width : win.width
            height: win.scr ? win.scr.height : win.height

        // ── centred stack: avatar · name · password ──
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -40 * win.ui
            spacing: 18
            scale: win.ui

            // avatar — the user's account icon (AccountsService copy is world-
            // readable, unlike ~/.face), circle-masked; initial as fallback
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 128; height: 128

                Rectangle {
                    anchors.fill: parent; radius: 64
                    color: pal.field; border.color: pal.stroke; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready
                        text: (win.userReal || win.userName || "?").charAt(0).toUpperCase()
                        color: pal.fgDim; font.family: pal.fontText; font.pixelSize: 52; font.weight: Font.Light
                    }
                }
                Image {
                    id: face
                    anchors.fill: parent
                    source: win.userName !== "" ? "file:///var/lib/AccountsService/icons/" + win.userName : ""
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 256; sourceSize.height: 256
                    layer.enabled: status === Image.Ready
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: faceMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }
                Item {
                    id: faceMask
                    anchors.fill: parent; layer.enabled: true; visible: false
                    Rectangle { anchors.fill: parent; radius: 64; antialiasing: true }
                }
                Rectangle {   // hairline rim so the photo edge reads crisp
                    anchors.fill: parent; visible: face.visible; radius: 64
                    color: "transparent"; border.color: pal.stroke; border.width: 1; antialiasing: true
                }
            }

            // username
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.userReal || win.userName || ""
                color: pal.fg; font.family: pal.fontText; font.pixelSize: 20; font.weight: Font.Medium
            }

            // password field
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300; height: 46; radius: 12
                color: pal.field
                border.color: pw.activeFocus ? pal.accent : (win.failed ? pal.danger : pal.stroke)
                border.width: pw.activeFocus || win.failed ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 120 } }

                TextInput {
                    id: pw
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password; passwordCharacter: "•"
                    color: pal.fg; font.family: pal.fontText; font.pixelSize: 15
                    enabled: !win.busy
                    focus: true; Component.onCompleted: forceActiveFocus()
                    onAccepted: win.submit()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pw.text.length === 0
                        text: "enter password"; color: pal.fgDim; font: pw.font
                    }
                }
                // submit arrow ("…" while checking)
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    text: win.busy ? "…" : "→"
                    color: win.busy ? pal.fgDim : pal.accent; font.family: pal.fontText; font.pixelSize: 18
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.submit() }
                }
            }

            // error line
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: win.statusMsg.length > 0
                text: win.statusMsg; color: win.failed ? pal.danger : pal.fgDim
                font.family: pal.fontText; font.pixelSize: 12
            }
        }

        // ── clock, bottom-left ──
        Column {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            anchors.leftMargin: 40 * win.ui; anchors.bottomMargin: 36 * win.ui
            spacing: 2
            scale: win.ui; transformOrigin: Item.BottomLeft
            Text { text: win.clockText; color: pal.fg; font.family: pal.fontText; font.pixelSize: 34; font.weight: Font.Light }
            Text { text: win.dateText; color: pal.fgDim; font.family: pal.fontText; font.pixelSize: 13 }
        }

        // ── session picker, bottom-right ──
        Item {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.rightMargin: 40 * win.ui; anchors.bottomMargin: 36 * win.ui
            width: 200; height: 38
            scale: win.ui; transformOrigin: Item.BottomRight

            // dropdown list (opens upward)
            Rectangle {
                id: menu
                visible: win.sessionMenuOpen && win.sessions.length > 0
                anchors.bottom: trigger.top; anchors.bottomMargin: 6; anchors.right: parent.right
                width: trigger.width; height: menuCol.height + 10; radius: 10
                color: pal.field; border.color: pal.stroke; border.width: 1
                Column {
                    id: menuCol; width: parent.width; y: 5
                    Repeater {
                        model: win.sessions
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 32
                            color: smA.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent"
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name; elide: Text.ElideRight
                                color: index === win.sessionIdx ? pal.accent : pal.fg
                                font.family: pal.fontText; font.pixelSize: 13
                            }
                            MouseArea { id: smA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { win.sessionIdx = index; win.sessionMenuOpen = false } }
                        }
                    }
                }
            }

            // trigger button
            Rectangle {
                id: trigger
                anchors.fill: parent; radius: 10
                color: trA.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent"
                border.color: pal.stroke; border.width: 1
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: chev.left; anchors.verticalCenter: parent.verticalCenter
                    text: win.sessions.length ? win.sessions[win.sessionIdx].name : "Session"
                    color: pal.fg; font.family: pal.fontText; font.pixelSize: 13; elide: Text.ElideRight
                }
                Text { id: chev; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: "▾"; color: pal.fgDim; font.pixelSize: 12 }
                MouseArea { id: trA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: win.sessionMenuOpen = !win.sessionMenuOpen }
            }
        }
        }   // stage
    }
}
