import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// ewe greeter — a Quickshell/QML login that matches the shell theme.
// Launched by greetd as:  cage -s -- qs -c ewe-greeter  (see phase 30).
// Layout mirrors the agreed mockup: centred avatar + username + password,
// clock bottom-left, session picker bottom-right, no power buttons.
//
// Quickshell's Greetd singleton speaks the greetd protocol for us:
//   createSession(user) → authMessage(...) → respond(pw) → readyToLaunch() → launch(argv)
FloatingWindow {
    id: win
    title: "ewe"
    implicitWidth: 1920
    implicitHeight: 1080
    color: pal.bg

    // ── palette: Ewe Dark, from the one source ──────────────────────────────
    // The greeter runs as the system `greeter` user, which reads none of the
    // person's dotfiles, so it wears the built-in Ewe Dark scheme (the lock
    // screen and power menu do too). Phase 30 writes those roles next to
    // this file at install time with
    //     ewe-theme --conf /dev/null build --scheme ewe-dark --json …/theme-tokens.json
    // — the same generator, the same derivation, no copied hex. A missing
    // file (a hand-copied greeter) falls back to plain black and white.
    FileView {
        id: tokFile
        path: String(Qt.resolvedUrl("theme-tokens.json")).replace(/^file:\/\//, "")
        blockLoading: true
        printErrors: false
    }
    QtObject {
        id: pal
        readonly property var tok: { try { return JSON.parse(tokFile.text()) } catch (e) { return ({}) } }
        function role(k, fb) { return (tok.color && tok.color[k]) || fb }
        function shape(k, fb) { return (tok.shape && tok.shape[k] !== undefined) ? tok.shape[k] : fb }
        readonly property color bg:      role("surface-base", "black")
        readonly property color fg:      role("text-primary", "white")
        readonly property color fgDim:   role("text-muted", "gray")
        readonly property color field:   role("surface-sunken", "black")   // the password box (Text field)
        readonly property color raised:  role("surface-raised", "black")   // the avatar disc, the session list
        readonly property color hover:   role("surface-hover", "dimgray")
        readonly property color stroke:  role("border-subtle", "dimgray")
        readonly property color fieldStroke: role("border-strong", "gray")
        readonly property color focus:   role("focus-ring", "white")
        readonly property color accent:  role("accent-text", "white")     // accent ink: the arrow, the chosen session
        readonly property color danger:  role("danger", "red")
        readonly property int radiusPrimary: shape("primary", 8)
        readonly property int radiusRounded: shape("rounded", 10)
        readonly property int borderWidth1:  shape("border-width-1", 1)
        readonly property int focusWidth:    shape("focus-width", 1)
        readonly property int fieldBorderWidth: shape("field-border-width", 1)
        // sizes and the type styles, from the same file (Ewe design system
        // v3 names; the fallbacks are the generator's defaults)
        function size(k, fb) { return (tok.size && tok.size[k] !== undefined) ? tok.size[k] : fb }
        readonly property int spaceXxs:  size("space-xxs", 2)
        readonly property int spaceXs:   size("space-xs", 4)
        readonly property int spaceS:    size("space-s", 8)
        readonly property int spaceMd:   size("space-md", 16)
        readonly property int spaceLg:   size("space-lg", 32)
        readonly property int controlLg: size("control-lg", 32)
        readonly property int controlXl: size("control-xl", 40)
        readonly property int icon4xl:   size("icon-4xl", 64)
        readonly property int panelSm:   size("panel-sm", 360)
        readonly property int panelMd:   size("panel-md", 400)
        readonly property int durFast:   (tok.motion && tok.motion.durFast !== undefined) ? tok.motion.durFast : 150
        readonly property int fontWeightLight:  (tok.type && tok.type.weight && tok.type.weight["font-weight-light"]) || 300
        readonly property int fontWeightMedium: (tok.type && tok.type.weight && tok.type.weight["font-weight-medium"]) || 500
        function px(style, fb) { return (tok.type && tok.type.styles && tok.type.styles[style]) ? tok.type.styles[style].size : fb }
        // Geist + Geist Mono, installed system-wide by phase 30
        // (/usr/share/fonts/ewe); /etc/fonts/conf.d/60-ewe-geist.conf puts
        // Noto Sans Georgian next in both stacks (Geist has no Georgian).
        readonly property string fontSans: (tok.type && tok.type.sans && tok.type.sans[0]) || "Geist"
        readonly property string fontMono: (tok.type && tok.type.mono && tok.type.mono[0]) || "Geist Mono"
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
    // Greetd.available is constant (GREETD_SOCK is read once at startup —
    // there is no availableChanged signal, a Connections on it only warned),
    // so auth starts when the user lookup below finishes.

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
                // default to the ewe session: the entry phase 30 renders (Exec =
                // start-hyprland.sh) whatever its Name is ("Hyprland (DE)" once,
                // "Ewe" now). The bare "Hyprland" entry beside it would start
                // without the wrapper: no session env, Hyprland's log on the VT.
                for (var j = 0; j < arr.length; j++)
                    if (/start-hyprland\.sh/.test(arr[j].exec) || /^ewe$/i.test(arr[j].name)) { win.sessionIdx = j; break }
            }
        }
    }
    // minute-aligned (the greeter shows "HH:mm") — see the shell's other clocks
    Timer {
        id: greeterClock
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            win.clockText = Qt.formatDateTime(d, "HH:mm")
            win.dateText = Qt.formatDateTime(d, "dddd, d MMMM")
            greeterClock.interval = 60000 - (Date.now() % 60000)
        }
    }

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
            anchors.verticalCenterOffset: -pal.spaceLg * win.ui
            spacing: pal.spaceMd
            scale: win.ui

            // avatar — the user's account icon (AccountsService copy is world-
            // readable, unlike ~/.face), circle-masked; initial as fallback
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 2 * pal.icon4xl; height: width

                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    color: pal.raised; border.color: pal.stroke; border.width: pal.borderWidth1
                    // brand fallback: the sheep mark (payload path first, then
                    // the packaged one); a bare initial only if both are absent
                    Image {
                        id: brandFace
                        anchors.centerIn: parent
                        width: pal.icon4xl; height: pal.icon4xl
                        visible: face.status !== Image.Ready && status === Image.Ready
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 2 * width; sourceSize.height: 2 * height
                        source: "file:///usr/share/ewe/system/branding/ewe-logo-dark.png"
                        onStatusChanged: if (status === Image.Error && source != "file:///usr/share/pixmaps/ewe-logo-dark.png")
                                             source = "file:///usr/share/pixmaps/ewe-logo-dark.png"
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready && brandFace.status !== Image.Ready
                        text: (win.userReal || win.userName || "?").charAt(0).toUpperCase()
                        color: pal.fgDim; font.family: pal.fontSans; font.pixelSize: pal.px("display-lg", 48); font.weight: pal.fontWeightLight
                    }
                }
                Image {
                    id: face
                    anchors.fill: parent
                    source: win.userName !== "" ? "file:///var/lib/AccountsService/icons/" + win.userName : ""
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 2 * width; sourceSize.height: 2 * height
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
                    Rectangle { anchors.fill: parent; radius: width / 2; antialiasing: true }
                }
                Rectangle {   // hairline rim so the photo edge reads crisp
                    anchors.fill: parent; visible: face.visible; radius: width / 2
                    color: "transparent"; border.color: pal.stroke; border.width: pal.borderWidth1; antialiasing: true
                }
            }

            // username
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.userReal || win.userName || ""
                color: pal.fg; font.family: pal.fontSans; font.pixelSize: pal.px("h3", 18); font.weight: pal.fontWeightMedium
            }

            // password field
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: pal.panelMd - 2 * pal.spaceLg; height: pal.controlXl; radius: pal.radiusPrimary
                color: pal.field
                // Text field: the border itself turns focus-ring, danger on error
                border.color: pw.activeFocus ? pal.focus : (win.failed ? pal.danger : pal.fieldStroke)
                border.width: pw.activeFocus ? pal.focusWidth : pal.fieldBorderWidth
                Behavior on border.color { ColorAnimation { duration: pal.durFast; easing.type: Easing.OutCubic } }

                TextInput {
                    id: pw
                    anchors.fill: parent; anchors.leftMargin: pal.spaceS + pal.spaceXs; anchors.rightMargin: pal.controlLg
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password; passwordCharacter: "•"
                    color: pal.fg; font.family: pal.fontSans; font.pixelSize: pal.px("body-lg", 15)
                    enabled: !win.busy
                    focus: true; Component.onCompleted: forceActiveFocus()
                    onAccepted: win.submit()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pw.text.length === 0
                        text: "Password"; color: pal.fgDim; font: pw.font
                    }
                }
                // submit arrow ("…" while checking)
                Text {
                    anchors.right: parent.right; anchors.rightMargin: pal.spaceS + pal.spaceXs; anchors.verticalCenter: parent.verticalCenter
                    text: win.busy ? "…" : "→"
                    color: win.busy ? pal.fgDim : pal.accent; font.family: pal.fontSans; font.pixelSize: pal.px("h3", 18)
                    MouseArea { anchors.fill: parent; anchors.margins: -pal.spaceS; cursorShape: Qt.PointingHandCursor; onClicked: win.submit() }
                }
            }

            // error line
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: win.statusMsg.length > 0
                text: win.statusMsg; color: win.failed ? pal.danger : pal.fgDim
                font.family: pal.fontSans; font.pixelSize: pal.px("caption", 11)
            }
        }

        // ── clock, bottom-left ──
        Column {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            anchors.leftMargin: pal.spaceLg * win.ui; anchors.bottomMargin: pal.spaceLg * win.ui
            spacing: pal.spaceXxs
            scale: win.ui; transformOrigin: Item.BottomLeft
            Text { text: win.clockText; color: pal.fg; font.family: pal.fontSans; font.pixelSize: pal.px("display", 36); font.weight: pal.fontWeightLight }
            Text { text: win.dateText; color: pal.fgDim; font.family: pal.fontSans; font.pixelSize: pal.px("body", 13) }
        }

        // ── session picker, bottom-right ──
        Item {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.rightMargin: pal.spaceLg * win.ui; anchors.bottomMargin: pal.spaceLg * win.ui
            width: pal.panelSm / 2; height: pal.controlXl
            scale: win.ui; transformOrigin: Item.BottomRight

            // dropdown list (opens upward)
            Rectangle {
                id: menu
                visible: win.sessionMenuOpen && win.sessions.length > 0
                anchors.bottom: trigger.top; anchors.bottomMargin: pal.spaceXs; anchors.right: parent.right
                width: trigger.width; height: menuCol.height + 2 * pal.spaceXs; radius: pal.radiusRounded
                color: pal.raised; border.color: pal.stroke; border.width: pal.borderWidth1
                Column {
                    id: menuCol; width: parent.width; y: pal.spaceXs
                    Repeater {
                        model: win.sessions
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: pal.controlLg
                            color: smA.containsMouse ? pal.hover : "transparent"
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: pal.spaceS + pal.spaceXs; anchors.right: parent.right; anchors.rightMargin: pal.spaceS + pal.spaceXs
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name; elide: Text.ElideRight
                                color: index === win.sessionIdx ? pal.accent : pal.fg
                                font.family: pal.fontSans; font.pixelSize: pal.px("body", 13)
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
                anchors.fill: parent; radius: pal.radiusPrimary
                color: trA.containsMouse ? pal.hover : "transparent"
                border.color: pal.stroke; border.width: pal.borderWidth1
                Text {
                    anchors.left: parent.left; anchors.leftMargin: pal.spaceS + pal.spaceXs; anchors.right: chev.left; anchors.verticalCenter: parent.verticalCenter
                    text: win.sessions.length ? win.sessions[win.sessionIdx].name : "Session"
                    color: pal.fg; font.family: pal.fontSans; font.pixelSize: pal.px("body", 13); elide: Text.ElideRight
                }
                Text { id: chev; anchors.right: parent.right; anchors.rightMargin: pal.spaceS + pal.spaceXs; anchors.verticalCenter: parent.verticalCenter
                    text: "▾"; color: pal.fgDim; font.family: pal.fontSans; font.pixelSize: pal.px("label", 12) }
                MouseArea { id: trA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: win.sessionMenuOpen = !win.sessionMenuOpen }
            }
        }
        }   // stage
    }
}
