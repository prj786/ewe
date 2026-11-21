import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

// Launcher — a centered, frosted app launcher with fuzzy search.
// Toggled via IPC:  qs ipc call applauncher toggle   (bound to Super+D).
Scope {
    id: root

    property bool opened: false
    property string query: ""
    property int selected: 0
    readonly property string home: Quickshell.env("HOME") || ""

    // apps (in-memory, instant) + files/folders (plocate, debounced) → merged list
    property var appResults: filterApps(query)
    property var fileResults: []
    property string fileQuery: ""
    property var results: mergeResults()

    function toggle() { opened = !opened }
    function hide()   { opened = false }

    // clear the INPUT too — resetting only `query` leaves the old text on
    // screen while the results are unfiltered (stale-search bug on reopen)
    // `held` keeps the window mapped through the close fade — the compositor's
    // layer fade is noanim'd for this namespace, so the QML must play it (set
    // on OPEN so no signal-order race can unmap early; see Overview.qml)
    property bool held: false
    property Timer _closeHold: Timer { interval: Math.max(1, Theme.durBase + 60); onTriggered: root.held = false }
    onOpenedChanged: {
        if (opened) { _closeHold.stop(); held = true; query = ""; input.text = ""; selected = 0; fileResults = []; if (!root.indexed && !indexProc.running) indexProc.running = true }
        else { _closeHold.restart(); if (!indexProc.running) indexProc.running = true }   // refresh the file index while nothing is on screen
    }
    onResultsChanged: if (selected >= results.length) selected = Math.max(0, results.length - 1)
    onQueryChanged: {
        var q = query.trim()
        if (q.length >= 2) fileDebounce.restart()
        else { fileDebounce.stop(); fileProc.running = false; fileResults = [] }
    }

    // `overview find <q>` (Globals.launcherFind): open with the query typed.
    // Opening resets the field synchronously, so the query lands after it.
    Connections {
        target: Globals
        function onLauncherFind(q) {
            root.opened = true
            input.text = String(q || "")
        }
    }

    IpcHandler {
        target: "applauncher"
        function toggle(): void { root.toggle() }
        function show(): void { root.opened = true }
        function hide(): void { root.opened = false }
    }
    // Super+D: hyprland.lua binds it to `hl.dsp.global("ewe:launcher")`, which
    // Hyprland delivers here over the global-shortcuts protocol — no
    // `sh -c qs ipc call …` per press (a Qt process start, ~20 ms, that also
    // swallowed the first letters typed). A press bind sends pressed AND
    // released, so toggle on pressed only. `qs ipc call applauncher toggle`
    // stays for scripts.
    GlobalShortcut {
        appid: "ewe"; name: "launcher"
        description: "Toggle the Launcher"
        onPressed: root.toggle()
    }

    // ── file/folder search (plocate, basename match, home-scoped, noise-filtered) ──
    // The launcher keeps ITS OWN index of $HOME (~/.cache/ewe/files.db): the
    // system one leaves /home out wherever it is a btrfs subvolume — updatedb
    // takes a subvolume mount for a bind mount and PRUNE_BIND_MOUNTS drops it
    // (2026-09-20: no file was ever found on a stock install). Indexing a
    // home takes well under a second, needs no root, and is redone in the
    // background once the index is 10 minutes old — on CLOSE, not on open:
    // the half second of disk and CPU it takes (375k files on a full home)
    // used to land on the open animation and the first keystrokes. Only the
    // very first index (none on disk yet) runs on open, so the first search
    // has something to answer; until it exists the system index answers.
    // Lowest CPU and I/O priority: the desktop must not notice it.
    readonly property string fileDb: "${XDG_CACHE_HOME:-$HOME/.cache}/ewe/files.db"
    readonly property string indexScript: "db=\"" + fileDb + "\"; mkdir -p \"${db%/*}\"; "
        + "if [ ! -s \"$db\" ] || [ -n \"$(find \"$db\" -mmin +10 2>/dev/null)\" ]; then "
        + "nice -n 19 ionice -c 3 updatedb -l 0 --prune-bind-mounts no -U \"$HOME\" -o \"$db.new\" --prunenames \".git .cache node_modules .cargo .rustup .npm .gradle\" 2>/dev/null "
        + "&& mv -f \"$db.new\" \"$db\"; fi"
    property bool indexed: false
    Process { id: indexProc; command: ["sh", "-c", root.indexScript]; onExited: root.indexed = true }
    // $1 = query; emits "<d|f>\t<abs-path>" per line so the icon can be a folder/file.
    // the first line echoes the query the run was started with: the one
    // collector serves every run, so a result must prove it is for the query
    // on screen (a killed run still flushes its partial output — 2026-09-20)
    readonly property string fileScript: "db=\"" + fileDb + "\"; printf \"q\\t%s\\n\" \"$1\"; "
        + "if [ -s \"$db\" ]; then plocate -d \"$db\" -i -b -l 2000 -- \"$1\"; else plocate -i -b -l 2000 -- \"$1\"; fi 2>/dev/null"
        + " | grep \"^$HOME/\" | grep -vE \"/(\\.cache|\\.git|\\.cargo|\\.rustup|\\.npm|\\.gradle|\\.mozilla|node_modules)/|/\\.var/app/[^/]+/cache/|/\\.local/share/Trash/\""
        + " | head -25 | while IFS= read -r p; do if [ -d \"$p\" ]; then printf \"d\\t%s\\n\" \"$p\"; else printf \"f\\t%s\\n\" \"$p\"; fi; done"

    Timer { id: fileDebounce; interval: 140; onTriggered: root.runFileSearch() }

    // A file result's icon from its name: the extension gives a MIME type,
    // the theme's icon for that type is tried first and the type's family
    // (image-x-generic, video-x-generic …) is the fallback — the same walk
    // the dock's Downloads panel does with the browser's MIME type. Every
    // file used to show the one text-page icon.
    readonly property var extMime: ({
        png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp",
        svg: "image/svg+xml", bmp: "image/bmp", tif: "image/tiff", tiff: "image/tiff", heic: "image/heif", avif: "image/avif",
        mp4: "video/mp4", mkv: "video/x-matroska", webm: "video/webm", mov: "video/quicktime", avi: "video/x-msvideo",
        mp3: "audio/mpeg", flac: "audio/flac", ogg: "audio/ogg", opus: "audio/ogg", wav: "audio/x-wav", m4a: "audio/mp4",
        pdf: "application/pdf", epub: "application/epub+zip",
        zip: "application/zip", tar: "application/x-tar", gz: "application/gzip", xz: "application/x-xz",
        zst: "application/zstd", "7z": "application/x-7z-compressed", rar: "application/vnd.rar",
        doc: "application/msword", docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        odt: "application/vnd.oasis.opendocument.text", xls: "application/vnd.ms-excel",
        xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ods: "application/vnd.oasis.opendocument.spreadsheet", csv: "text/csv",
        ppt: "application/vnd.ms-powerpoint", pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        odp: "application/vnd.oasis.opendocument.presentation",
        txt: "text/plain", md: "text/markdown", html: "text/html", htm: "text/html", json: "application/json",
        xml: "application/xml", yaml: "application/x-yaml", yml: "application/x-yaml", toml: "application/toml",
        sh: "application/x-shellscript", py: "text/x-python", js: "text/javascript", ts: "text/x-typescript",
        rs: "text/rust", c: "text/x-csrc", h: "text/x-chdr", cpp: "text/x-c++src", go: "text/x-go", lua: "text/x-lua",
        qml: "text/x-qml", css: "text/css", ttf: "font/ttf", otf: "font/otf", woff2: "font/woff2",
        iso: "application/x-cd-image", appimage: "application/vnd.appimage", deb: "application/vnd.debian.binary-package",
        exe: "application/x-ms-dos-executable", desktop: "application/x-desktop"
    })
    function fileIcon(name) {
        var dot = name.lastIndexOf(".")
        var ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : ""
        var mime = root.extMime[ext] || ""
        var p = mime !== "" ? Quickshell.iconPath(mime.replace("/", "-"), true) : ""
        if (p === "") {
            var major = mime.split("/")[0]
            p = Quickshell.iconPath(["audio", "video", "image", "text", "font"].indexOf(major) >= 0
                                    ? major + "-x-generic" : "text-x-generic", "text-x-generic")
        }
        return p
    }

    Process {
        id: fileProc
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), arr = []
                var ran = (lines[0] || "").indexOf("q\t") === 0 ? lines[0].slice(2) : null
                var want = root.query.trim()
                // not the query on screen (typed past, or cleared to nothing): drop it
                if (ran === null || ran !== want || want.length < 2) return
                var q = ran.toLowerCase()
                for (var i = 1; i < lines.length; i++) {
                    var ln = lines[i]; if (!ln) continue
                    var t = ln.indexOf("\t"); if (t < 0) continue
                    var isDir = ln.charAt(0) === "d"
                    var path = ln.slice(t + 1)
                    var slash = path.lastIndexOf("/")
                    var nm = path.slice(slash + 1)
                    var dir = path.slice(0, slash)
                    var disp = (root.home && dir.indexOf(root.home) === 0) ? "~" + dir.slice(root.home.length) : dir
                    arr.push({ type: "file", isDir: isDir, path: path, name: nm, sub: disp,
                               iconSource: isDir ? Quickshell.iconPath("folder", "folder") : root.fileIcon(nm) })
                }
                // basename-prefix matches first, then shortest name
                arr.sort(function (a, b) {
                    var ap = a.name.toLowerCase().indexOf(q) === 0 ? 0 : 1
                    var bp = b.name.toLowerCase().indexOf(q) === 0 ? 0 : 1
                    if (ap !== bp) return ap - bp
                    return a.name.length - b.name.length
                })
                root.fileResults = arr
            }
        }
    }

    // ── fuzzy ranking ─────────────────────────────────────────────────────
    function filterApps(q) {
        var all = DesktopEntries.applications.values
        var vis = []
        for (var i = 0; i < all.length; i++)
            if (!all[i].noDisplay) vis.push(all[i])

        q = q.trim().toLowerCase()
        if (q.length === 0) {
            vis.sort(function (a, b) {
                return (a.name || "").toLowerCase() < (b.name || "").toLowerCase() ? -1 : 1
            })
            return vis
        }
        var scored = []
        for (var j = 0; j < vis.length; j++) {
            var s = scoreEntry(vis[j], q)
            if (s > 0) scored.push({ e: vis[j], s: s, n: (vis[j].name || "").toLowerCase() })
        }
        scored.sort(function (a, b) { return b.s - a.s || (a.n < b.n ? -1 : 1) })
        var out = []
        for (var k = 0; k < scored.length; k++) out.push(scored[k].e)
        return out
    }

    // `name` is in the session's language (Name[ka]); the untranslated Name
    // (Globals.englishName, from desktop-entries.py) scores the same, so an
    // app is found by either — "Files" and "ფაილები" both find ewe Files
    function scoreEntry(e, q) {
        var name = (e.name || "").toLowerCase()
        var en   = Globals.englishName(e).toLowerCase()
        var gen  = (e.genericName || "").toLowerCase()
        var com  = (e.comment || "").toLowerCase()
        if (name === q || en === q) return 1000
        if (name.indexOf(q) === 0 || (en !== "" && en.indexOf(q) === 0)) return 850
        if (name.indexOf(" " + q) >= 0 || (en !== "" && en.indexOf(" " + q) >= 0)) return 700      // word start
        if (name.indexOf(q) >= 0 || (en !== "" && en.indexOf(q) >= 0)) return 500
        if (gen.indexOf(q) >= 0) return 280
        if (com.indexOf(q) >= 0) return 120
        return 0
    }

    // ── merge apps + files into one normalized result list ────────────────
    // each item: { type:"app"|"file", name, sub, iconSource, entry?|path?, isDir? }
    // synthetic in-shell actions (e.g. open Settings) surfaced when the query matches
    // Only what has no .desktop entry of its own. ewe-settings ships
    // ewe-settings.desktop, so listing Settings here too put TWO identical
    // results in the launcher that opened the same window. The synthetic one
    // survives solely for a machine where the app is absent and the in-shell
    // fallback panel is the only Settings there is.
    readonly property var actions: Globals.settingsAppInstalled ? [] : [
        { name: "ewe Settings", sub: "System preferences", ic: "preferences-system", run: function () { Quickshell.execDetached(["qs", "ipc", "call", "settings", "toggle"]) } }
    ]
    function matchActions(q) {
        if (q === "") return []
        var out = []
        for (var i = 0; i < root.actions.length; i++) if (root.actions[i].name.toLowerCase().indexOf(q.toLowerCase()) >= 0) out.push(root.actions[i])
        return out
    }

    function mergeResults() {
        var out = []
        var a = root.appResults
        var hasQuery = root.query.trim().length > 0
        var acts = root.matchActions(root.query.trim())
        for (var ai = 0; ai < acts.length; ai++) out.push({ type: "action", name: acts[ai].name, sub: acts[ai].sub, iconSource: Quickshell.iconPath(acts[ai].ic, "preferences-system"), run: acts[ai].run })
        var capA = hasQuery ? Math.min(a.length, 6) : a.length   // leave room for files
        for (var i = 0; i < capA; i++) {
            var e = a[i]
            out.push({ type: "app", entry: e, name: e.name || "",
                       sub: e.genericName || e.comment || "",
                       iconSource: Quickshell.iconPath(e.icon, "application-x-executable") })
        }
        var f = root.fileResults
        for (var j = 0; j < f.length; j++) out.push(f[j])
        return out
    }

    function runFileSearch() {
        var q = root.query.trim()
        if (q.length < 2) { root.fileResults = []; return }
        root.fileQuery = q
        fileProc.running = false
        fileProc.command = ["sh", "-c", root.fileScript, "sh", q]
        fileProc.running = true
    }

    function launch(item, fresh) {
        if (!item) return
        // focus-or-launch: jump to the app's existing window unless a new
        // instance was explicitly asked for (middle click / fresh=true)
        if (item.type === "app") { Globals.launchEntry(item.entry, fresh) }
        else if (item.type === "action") { if (item.run) item.run() }
        else Quickshell.execDetached(["xdg-open", item.path])
        root.hide()
    }

    // ── the result's right-click menu (ContextMenu): an app — Open, New
    //    window, its desktop actions, Pin / Unpin; a file — Open, Open
    //    with… (the file selected in Files, where Open with lives), its
    //    folder, Copy path. The launcher keeps the keyboard (its field),
    //    so it forwards keys to the menu while one is open ──
    ContextMenu { id: rowMenu; name: "launcher-menu"; takesKeyboard: false }
    Connections { target: root; function onOpenedChanged() { if (!root.opened) rowMenu.close() } }
    function pinIdOf(e) { return e && e.id ? String(e.id).replace(/\.desktop$/, "") + ".desktop" : "" }
    function menuFor(item) {
        if (!item) return []
        var out = [{ header: item.name || "" }]
        if (item.type === "app") {
            var e = item.entry, pid = root.pinIdOf(e)
            out.push({ label: "Open", action: function () { root.launch(item, false) } })
            out.push({ label: "New window", icon: Theme.icPlus, action: function () { root.launch(item, true) } })
            var acts = (e && e.actions) ? e.actions : []
            if (acts.length > 0) {
                out.push({ separator: true })
                for (var i = 0; i < acts.length; i++) (function (a) {
                    out.push({ label: a.name || "", action: function () { a.execute(); root.hide() } })
                })(acts[i])
            }
            out.push({ separator: true })
            var pinned = Globals.isPinned(pid)
            out.push({ label: pinned ? "Unpin from dock" : "Pin to dock", icon: pinned ? Theme.icPinOff : Theme.icPin,
                       disabled: pid === "", action: function () { Globals.setPinned(pid, !pinned) } })
        } else if (item.type === "file") {
            var dir = item.isDir ? item.path : (item.path.slice(0, Math.max(0, item.path.lastIndexOf("/"))) || "/")
            out.push({ label: "Open", action: function () { root.launch(item, false) } })
            out.push({ label: "Open with…", action: function () { Quickshell.execDetached(["ewe-files-app", "--open-with=" + item.path]); root.hide() } })
            out.push({ label: "Open containing folder", icon: Theme.icFolder, action: function () { Quickshell.execDetached(item.isDir ? ["ewe-files-app", dir] : ["ewe-files-app", "--select=" + item.path]); root.hide() } })
            out.push({ separator: true })
            out.push({ label: "Copy path", icon: Theme.icClipboard, action: function () { Quickshell.execDetached(["wl-copy", "--", item.path]); Shell.toast("Path copied") } })
        } else return []
        return out
    }
    function openMenuFor(index, item, x, y) {
        root.selected = index
        rowMenu.items = root.menuFor(root.results[index])
        rowMenu.openAt(item, x, y)
    }

    // ── the overlay window ────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.opened || root.held
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:applauncher"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: if (visible) input.forceActiveFocus()

        // click anywhere outside the panel → dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        // ── a keyboard key, for the search hint and the footer ──
        component Kbd: Rectangle {
            property string key: ""
            implicitWidth: Math.max(Theme.lineHeightS + 3 * Theme.borderWidth1,
                                    kt.implicitWidth + 2 * Theme.spaceXs)
            implicitHeight: kt.implicitHeight + 2 * Theme.borderWidth2
            radius: Theme.radiusSlight
            color: Theme.surfaceRaised
            border.color: Theme.borderStrong
            border.width: Theme.borderWidth1
            Text {
                id: kt
                anchors.centerIn: parent
                text: parent.key
                color: Theme.textSecondary
                font.family: Theme.type.mono.family
                font.pixelSize: Theme.type.caption.size
                font.weight: Theme.fontWeightMedium
            }
        }

        // ── centered panel (sits in the upper third) ──
        Item {
            id: panelWrap
            width: Theme.panelLg
            height: panel.height
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.20

            opacity: root.opened ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }

            Rectangle {
                id: panel
                width: parent.width
                height: content.implicitHeight
                // the panel radius plus a step, so the rows inside stay
                // concentric with it (Launcher card #1)
                radius: Theme.r(Theme.radiusRounded + Theme.spaceXs)
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                clip: true
                layer.enabled: true
                layer.effect: Elevation {}

                // swallow clicks inside the panel so they don't dismiss it
                MouseArea { anchors.fill: parent }

                Column {
                    id: content
                    width: parent.width

                    // ── search row: the xl Search field, borderless inside
                    //    the panel, with Esc as its hint (Launcher card #2) ──
                    Item {
                        id: searchRow
                        width: parent.width
                        height: Theme.controlXl + 2 * Theme.spaceS
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceMd
                            anchors.rightMargin: Theme.spaceMd
                            spacing: Theme.spaceS
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icSearch
                                font.family: Theme.fontIcons
                                font.pixelSize: Theme.iconLg
                                color: Theme.textMuted
                            }
                            TextInput {
                                id: input
                                width: parent.width - Theme.iconLg - escHint.width - 2 * Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                // typed Arabic or Hebrew starts by the search
                                // glyph like everything else, not across the
                                // field by the Esc key
                                horizontalAlignment: TextInput.AlignLeft
                                color: Theme.textPrimary
                                font.family: Theme.type.bodyLg.family
                                font.pixelSize: Theme.type.bodyLg.size
                                selectionColor: Theme.accent
                                selectByMouse: true
                                clip: true
                                onTextChanged: { root.query = text; root.selected = 0 }
                                Text {
                                    visible: input.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Search apps, settings and files"
                                    color: Theme.textMuted
                                    font: input.font
                                }
                                Keys.onPressed: function (ev) {
                                    // an open result menu takes the keys first
                                    if (rowMenu.handleKey(ev)) { ev.accepted = true; return }
                                    // the Menu key (or Shift+F10) opens the selected result's menu
                                    if (ev.key === Qt.Key_Menu || (ev.key === Qt.Key_F10 && (ev.modifiers & Qt.ShiftModifier))) {
                                        var it = list.itemAtIndex(root.selected)
                                        if (it) root.openMenuFor(root.selected, it, it.width / 2, it.height / 2)
                                        ev.accepted = true; return
                                    }
                                    // Esc clears the query, a second Esc closes
                                    if (ev.key === Qt.Key_Escape) {
                                        if (input.text !== "") input.text = ""; else root.hide()
                                        ev.accepted = true
                                    }
                                    else if (ev.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Up)   { root.selected = Math.max(root.selected - 1, 0); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.launch(root.results[root.selected]); ev.accepted = true }
                                }
                            }
                            Kbd { id: escHint; anchors.verticalCenter: parent.verticalCenter; key: "Esc" }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: Theme.borderWidth1
                        color: Theme.borderSubtle
                        visible: root.results.length > 0
                    }

                    // ── results: control2xl rows with an icon2xl icon, the
                    //    title at body weight medium, the folder or generic
                    //    name as a caption, and the running key as the hint ──
                    ListView {
                        id: list
                        width: parent.width
                        // at most 8 rows, and never past the bottom of the
                        // screen — the footer's hints must stay visible
                        // (the rows PLUS the list's own top/bottom margins:
                        // without them the content is 2 × spaceXs taller than
                        // the list and the last row's fill touches the footer)
                        height: Math.min(Math.min(root.results.length, 8) * Theme.control2xl + topMargin + bottomMargin,
                                         Math.max(Theme.control2xl + topMargin + bottomMargin,
                                                  win.height - panelWrap.y - searchRow.height
                                                  - foot.height - Theme.spaceLg))
                        topMargin: root.results.length > 0 ? Theme.spaceXs : 0
                        bottomMargin: root.results.length > 0 ? Theme.spaceXs : 0
                        clip: true
                        model: root.results
                        currentIndex: root.selected
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: row
                            width: list.width
                            height: Theme.control2xl
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.selected

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spaceS
                                anchors.rightMargin: Theme.spaceS
                                radius: Theme.radiusPrimary
                                // selection is a surface step, never an accent
                                // fill: the row's own text has to stay readable
                                // (pointing at a row selects it, so hover and the
                                // keyboard selection are the same surfaceHover)
                                color: row.sel || rowMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spaceMd
                                anchors.rightMargin: Theme.spaceMd
                                spacing: Theme.spaceS + Theme.spaceXs
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.icon2xl; height: Theme.icon2xl
                                    sourceSize.width: 2 * Theme.icon2xl; sourceSize.height: 2 * Theme.icon2xl
                                    mipmap: true
                                    source: row.modelData.iconSource || Quickshell.iconPath("application-x-executable")
                                }
                                // name and line beside the icon, both stopping
                                // short of the Enter key and set from the icon
                                // side whatever the script: Arabic or Hebrew
                                // used to slide right, under the key (a row is
                                // not a paragraph; ewe's chrome is not mirrored)
                                Column {
                                    readonly property real textW: row.width - 2 * Theme.spaceMd - Theme.icon2xl
                                                                  - parent.spacing - enterKey.width - Theme.spaceS
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: row.modelData.name || ""
                                        width: Math.min(implicitWidth, parent.textW)
                                        horizontalAlignment: Text.AlignLeft
                                        elide: Text.ElideRight
                                        color: Theme.textPrimary
                                        font.family: Theme.type.bodyStrong.family
                                        font.pixelSize: Theme.type.bodyStrong.size
                                        font.weight: Theme.fontWeightMedium
                                    }
                                    Text {
                                        text: row.modelData.sub || ""
                                        visible: text.length > 0
                                        color: Theme.textMuted
                                        font.family: Theme.type.caption.family
                                        font.pixelSize: Theme.type.caption.size
                                        horizontalAlignment: Text.AlignLeft
                                        elide: Text.ElideRight
                                        width: parent.textW
                                    }
                                }
                            }
                            // the trailing hint: the key that runs the selection
                            Kbd {
                                id: enterKey
                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceMd
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.sel
                                key: "Enter"
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                onPositionChanged: root.selected = row.index
                                onClicked: function (mouse) {
                                    if (mouse.button === Qt.RightButton) root.openMenuFor(row.index, rowMa, mouse.x, mouse.y)
                                    else root.launch(row.modelData, mouse.button === Qt.MiddleButton)
                                }
                            }
                        }
                    }

                    // ── footer: what the keyboard does, on surfaceBase ──
                    // It reaches the panel's edge, so it takes the panel's
                    // bottom corners and outline (its top edge is the
                    // divider) — a plain rectangle painted square corners
                    // over the rounded panel (clip is rectangular).
                    Rectangle {
                        id: foot
                        width: parent.width
                        height: hints.implicitHeight + 2 * Theme.spaceS
                        color: Theme.surfaceBase
                        border.color: Theme.borderSubtle
                        border.width: Theme.borderWidth1
                        bottomLeftRadius: panel.radius
                        bottomRightRadius: panel.radius
                        Row {
                            id: hints
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            spacing: Theme.spaceMd
                            Row {
                                spacing: Theme.spaceXs
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "↑" }
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "↓" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Move"; color: Theme.textMuted
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                }
                            }
                            Row {
                                spacing: Theme.spaceXs
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "Enter" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Open"; color: Theme.textMuted
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                }
                            }
                            Row {
                                spacing: Theme.spaceXs
                                Kbd { anchors.verticalCenter: parent.verticalCenter; key: "Esc" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Close"; color: Theme.textMuted
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
