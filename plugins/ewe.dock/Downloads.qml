import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Downloads (dock 1.2.0) — the ewe browser's downloads, on the dock.
//
// The source is the browser's own record, `$XDG_CONFIG_HOME/ewe-browser/
// downloads.json` ({version: 1, entries: [{id, url, filename, path, mime,
// received, total, speed, status, started, ended}]}, newest first, times in
// ms). The browser writes it atomically, at most once a second while
// anything runs; a FileView watches it, so the dock spends nothing while
// nothing downloads — no poll, no process. (The browser's CLI,
// `ewe-browser downloads`, prints the same list but starts Electron's Node
// for every call: fine for a script, far too heavy for a progress ring.)
//
// The dock button shows while a download runs (with a progress ring) or one
// finished in the last day; "Clear" hides those that are there now — the
// mark is local (~/.local/state/ewe/dock-downloads.json), never ewe.conf:
// it is this machine's list, not a setting to sync.
Scope {
    id: dl

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (dl.home + "/.config")
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (dl.home + "/.local/state")
    readonly property string downloadsDir: dl.home + "/Downloads"

    // "recent" is a day; the clock that ages entries out ticks once a minute
    readonly property real dayMs: 24 * 60 * 60 * 1000
    readonly property int minute: 60 * 1000
    property real now: Date.now()
    Timer { interval: dl.minute; running: true; repeat: true; onTriggered: dl.now = Date.now() }

    property var entries: []
    property real clearedAt: 0

    FileView {
        id: record
        path: dl.configDir + "/ewe-browser/downloads.json"
        watchChanges: true
        printErrors: false
        onFileChanged: record.reload()
        onLoaded: { dl.missing = false; dl.parse(record.text()) }
        onLoadFailed: { dl.missing = true; dl.entries = [] }
    }
    // A watch needs the file: until the browser's first download writes it,
    // look again every few seconds (a failed open, nothing more); from then
    // on the watch carries it.
    property bool missing: false
    readonly property int retryMs: 5 * 1000
    Timer { interval: dl.retryMs; running: dl.missing; repeat: true; onTriggered: record.reload() }
    function parse(t) {
        var o = null
        try { o = JSON.parse(t) } catch (e) { o = null }
        dl.entries = (o && Array.isArray(o.entries)) ? o.entries : []
        dl.now = Date.now()
    }

    FileView {
        id: mark
        path: dl.stateDir + "/ewe/dock-downloads.json"
        printErrors: false
        onLoaded: {
            var o = null
            try { o = JSON.parse(mark.text()) } catch (e) { o = null }
            dl.clearedAt = (o && typeof o.clearedAt === "number") ? o.clearedAt : 0
        }
    }
    function clear() {
        dl.clearedAt = Date.now()
        mark.setText(JSON.stringify({ clearedAt: dl.clearedAt }) + "\n")
        pop.close()
    }

    function live(e) { return e.status === "progressing" || e.status === "paused" }
    // what the panel lists: running ones, and the day's finished ones, since "Clear"
    readonly property var recent: {
        var out = []
        for (var i = 0; i < dl.entries.length && out.length < 8; i++) {
            var e = dl.entries[i]
            if (!e || (e.started || 0) <= dl.clearedAt) continue
            if (dl.live(e) || (e.ended && dl.now - e.ended < dl.dayMs)) out.push(e)
        }
        return out
    }
    readonly property bool shown: dl.recent.length > 0
    readonly property var running: dl.recent.filter(function (e) { return e.status === "progressing" })
    readonly property bool busy: dl.running.length > 0
    // 0..1 over everything running, or -1 while a size is unknown
    readonly property real progress: {
        var got = 0, all = 0
        for (var i = 0; i < dl.running.length; i++) {
            if (!(dl.running[i].total > 0)) return -1
            got += dl.running[i].received || 0
            all += dl.running[i].total
        }
        return all > 0 ? Math.min(1, got / all) : -1
    }
    // a download just landed: the dock button says so for a moment
    property bool landed: false
    Timer { id: landedHold; interval: Math.max(1, Theme.durDim); onTriggered: dl.landed = false }
    onBusyChanged: if (!dl.busy && dl.recent.length > 0 && dl.recent[0].status === "completed") { dl.landed = true; landedHold.restart() }

    // ── formatting ─────────────────────────────────────────────────────────
    function size(n) {
        n = n || 0
        if (n < 1000) return n + " B"
        var u = ["kB", "MB", "GB", "TB"], i = -1
        do { n /= 1000; i++ } while (n >= 1000 && i < u.length - 1)
        return (n < 10 ? n.toFixed(1) : Math.round(n)) + " " + u[i]
    }
    function ago(t) {
        var m = Math.floor((dl.now - t) / dl.minute)
        if (m < 1) return "just now"
        if (m < 60) return m + " min ago"
        var h = Math.floor(m / 60)
        return h < 24 ? h + " h ago" : "yesterday"
    }
    function status(e) {
        if (e.status === "progressing")
            return e.total > 0 ? dl.size(e.received) + " of " + dl.size(e.total) : dl.size(e.received)
        if (e.status === "paused") return "Paused · " + dl.size(e.received) + (e.total > 0 ? " of " + dl.size(e.total) : "")
        if (e.status === "cancelled") return "Cancelled"
        if (e.status === "interrupted") return "Failed"
        return dl.size(e.total || e.received) + " · " + dl.ago(e.ended || e.started)
    }
    function iconFor(e) {
        var mime = String(e.mime || "")
        var p = mime !== "" ? Quickshell.iconPath(mime.replace("/", "-"), true) : ""
        if (p === "") {
            var major = mime.split("/")[0]
            p = Quickshell.iconPath(["audio", "video", "image", "text", "font"].indexOf(major) >= 0
                                    ? major + "-x-generic" : "text-x-generic", "text-x-generic")
        }
        return p
    }

    // ── actions ────────────────────────────────────────────────────────────
    function openFile(e) {
        if (!e || e.status !== "completed" || !e.path) return
        Quickshell.execDetached(["xdg-open", e.path])
        pop.close()
    }
    // the file selected in the file manager (FileManager1, which Nemo,
    // Nautilus and Dolphin all speak), else its folder opened
    function reveal(e) {
        if (!e || !e.path) return
        var uri = "file://" + encodeURI(e.path).replace(/'/g, "%27")
        var dir = e.path.substring(0, e.path.lastIndexOf("/")) || "/"
        Quickshell.execDetached(["sh", "-c",
            'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 ' +
            '--method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 || xdg-open "$2"',
            "ewe-dock", uri, dir])
        pop.close()
    }
    function openFolder() { Quickshell.execDetached(["xdg-open", dl.downloadsDir]); pop.close() }
    // a running download: the browser has the controls
    function toBrowser() { Shell.focusApp(["ewe-browser"]); pop.close() }

    readonly property bool open: pop.open
    function toggleAt(a) { pop.toggleAt(a) }
    function close() { pop.close() }

    readonly property int rowH: Theme.control2xl
    AnchoredPopup {
        id: pop
        name: "downloads"
        owner: "ewe.dock.downloads"
        action: "ewe.dock.downloads"
        implicitWidth: Theme.panelSm
        implicitHeight: Theme.spaceS + Theme.controlLg + Theme.spaceXs
                        + Math.max(1, dl.recent.length) * (dl.rowH + Theme.spaceXxs) + Theme.spaceS

        Item {
            anchors.fill: parent
            anchors.margins: Theme.spaceS

            Item {
                id: head
                width: parent.width; height: Theme.controlLg
                TextStrong {
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Downloads"
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceXs
                    QsIconButton { ic: Theme.icFolder; onGo: dl.openFolder(); Accessible.name: "Open the Downloads folder" }
                    QsButton { variant: "ghost"; label: "Clear"; visible: dl.recent.length > dl.running.length; onGo: dl.clear() }
                }
            }

            Column {
                anchors.top: head.bottom; anchors.topMargin: Theme.spaceXs
                width: parent.width
                spacing: Theme.spaceXxs

                Repeater {
                    model: dl.recent
                    delegate: Item {
                        id: row
                        required property var modelData
                        readonly property bool running: modelData.status === "progressing" || modelData.status === "paused"
                        readonly property bool done: modelData.status === "completed"
                        readonly property bool failed: modelData.status === "cancelled" || modelData.status === "interrupted"
                        width: parent.width; height: dl.rowH

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusPrimary
                            color: rowMa.containsMouse ? Theme.surfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        }
                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: row.failed ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: row.done ? dl.openFile(row.modelData) : row.running ? dl.toBrowser() : undefined
                        }
                        Image {
                            id: fileIcon
                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconXl; height: Theme.iconXl
                            sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl; mipmap: true
                            source: dl.iconFor(row.modelData)
                            opacity: row.failed ? Theme.opacityGlass : 1
                        }
                        Column {
                            anchors.left: fileIcon.right; anchors.leftMargin: Theme.spaceS
                            anchors.right: revealBtn.left; anchors.rightMargin: Theme.spaceXs
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceXxs
                            TextBody {
                                width: parent.width
                                text: row.modelData.filename || "Download"
                                elide: Text.ElideMiddle
                                color: row.failed ? Theme.textSecondary : Theme.textPrimary
                            }
                            // the bar only while it runs (Progress bar card: track
                            // surfaceHover, accent fill; paused keeps its place)
                            Rectangle {
                                visible: row.running
                                width: parent.width; height: Theme.borderWidth2 * 2
                                radius: Theme.radiusFull
                                color: Theme.surfaceHover
                                Rectangle {
                                    height: parent.height; radius: Theme.radiusFull
                                    width: row.modelData.total > 0 ? Math.round(parent.width * Math.min(1, row.modelData.received / row.modelData.total)) : 0
                                    color: row.modelData.status === "paused" ? Theme.textMuted : Theme.accent
                                    Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.ease } }
                                }
                            }
                            TextCaption {
                                width: parent.width
                                text: dl.status(row.modelData)
                                color: row.failed ? Theme.danger : Theme.textSecondary
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        QsIconButton {
                            id: revealBtn
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.done
                            ic: Theme.icFolder
                            onGo: dl.reveal(row.modelData)
                            Accessible.name: "Show in folder"
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: (row.modelData.filename || "Download") + ", " + dl.status(row.modelData)
                    }
                }

                // cleared while nothing runs: one quiet line
                TextBody {
                    visible: dl.recent.length === 0
                    width: parent.width; height: dl.rowH
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "No recent downloads"
                    color: Theme.textSecondary
                }
            }
        }
    }
}
