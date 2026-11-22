import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// FilePicker — "Open", "Save as" and "Choose a folder" for EVERY app
// (RFC-011, design system: File picker).
//
// Apps ask xdg-desktop-portal for a file; ewe routes that to ewe-portal
// (bin/ewe-portal), which writes the request to a file and asks us over IPC:
//
//     qs ipc call filepicker open <request.json>   → "ok"
//     qs ipc call filepicker close <id>            the app gave up
//     qs ipc call filepicker ping <id>             "open" · "idle" · "unknown"
//     qs ipc call filepicker select <answer-json>  a scripted answer (tests)
//     qs ipc call filepicker cancel
//
// and we answer on ewe-portal's bus name — org.ewe.Portal1.Answer(id, json),
// which says `b false` for an answer it cannot use (the picker stays open).
// One request at a time: ewe-portal queues the rest. When we cannot answer
// (no shell, a QML error, a restart) it hands the request to the GTK dialog.
//
// Why a layer surface: the stock dialog was an ordinary window and opened
// UNDER the app that asked whenever that app was floating, fullscreen or an
// X11 window. An Overlay layer is above every window, fullscreen included.
// The window exists only while a request is open (LazyLoader), with the
// keyboard Exclusive; when it goes, Hyprland hands focus back to the app.
//
//   card     at most panelLg + panelSm less spaceLg + spaceS (880) wide and
//            panelLg + spaceXl (624) tall, spaceXl + spaceMd (80) from the
//            screen edges; surfaceRaised, a borderWidth1 borderSubtle
//            outline, radiusRounded, shadowFloat, spaceMd padding and between
//            sections, over `scrim` (a click on it does nothing — Dialog)
//   header   the app's iconXl icon, the title in h3, the app's name in caption
//            textMuted, a close Icon button
//   places   panelSm / 2 (180) wide: Recent, Home and the XDG folders, then
//            the account's folders, pins and drives under overline headers;
//            dense List rows, the current one accentSubtle
//   toolbar  Back · Forward · Up (md ghost Icon buttons), the breadcrumb
//            (Breadcrumb card), search, then New folder · hidden files ·
//            list or grid on the right; Ctrl+L or typing / or ~ turns the
//            breadcrumb into a path field
//   list     in a surfaceSunken well: controlLg rows, an iconMd glyph
//            (folders in accentText), the name in body, size and date in
//            caption textMuted under a column header that sorts; selected
//            accentSubtle, the keyboard cursor a focusWidth focusRing
//   grid     square cells of 2 × control2xl + spaceMd: a picture's thumbnail
//            (icon4xl, decoded small) or the glyph at icon3xl, two caption lines
//   save     the Name field above the footer, the base name preselected
//   footer   above a borderWidth1 divider: the app's file types and options
//            (Select-style buttons, checkboxes) on the left; Cancel (ghost)
//            and the primary action on the right. A line above it asks
//            "Replace …?" (warning) or says what went wrong (danger).
Scope {
    id: root

    // ── the request ─────────────────────────────────────────────────────────
    property var req: null
    readonly property bool open: root.req !== null
    readonly property string kind: root.req ? root.req.kind : ""
    readonly property bool multiple: !!(root.req && root.req.multiple) && root.kind === "open"
    readonly property bool pickFolder: root.kind === "folder" || root.kind === "saves"
    readonly property bool saving: root.kind === "save"
    readonly property var filters: root.req && root.req.filters ? root.req.filters : []
    readonly property var choices: root.req && root.req.choices ? root.req.choices : []
    readonly property var places: root.req && root.req.places ? root.req.places : []
    readonly property string home: root.req && root.req.home ? root.req.home : Quickshell.env("HOME")

    // who asked: the window that had focus when the request came in
    property string appCls: ""
    readonly property string rememberKey: root.req && root.req.app_id ? root.req.app_id : root.appCls

    // ── view state ──────────────────────────────────────────────────────────
    property string view: "list"
    property bool showHidden: false
    property string sortKey: "name"          // name · modified · size
    property bool sortDesc: false
    property string folder: ""
    property bool recentMode: false
    property var back: []
    property var fwd: []
    property int filterIdx: 0
    property var choiceValues: ({})
    property string search: ""
    property string saveName: ""
    property string confirm: ""              // the "Replace …?" question
    property string error: ""
    property bool busy: false
    property bool editingPath: false
    property bool makingFolder: false
    property string pendingSelect: ""        // select this path once its folder lists

    // the folder's entries (FolderListModel, inside the window) and the shown slice
    property var entries: []
    property bool loading: false
    readonly property var globs: (root.filters.length > 0 && root.filterIdx >= 0 && root.filterIdx < root.filters.length)
                                 ? root.filters[root.filterIdx].globs : ["*"]
    readonly property var recentEntries: {
        var out = [], list = root.req && root.req.recent ? root.req.recent : []
        var re = root.globRegex(root.globs)
        for (var i = 0; i < list.length; i++) {
            var p = String(list[i].path), name = root.baseName(p)
            if (re && !re.test(name)) continue
            if (!root.showHidden && name.charAt(0) === ".") continue
            out.push({ name: name, path: p, dir: false, size: -1, mtime: new Date(list[i].time * 1000),
                       where: root.prettyDir(root.dirName(p)) })
        }
        return out
    }
    readonly property var shown: {
        var src = root.recentMode ? root.recentEntries : root.entries
        var q = root.search.trim().toLowerCase(), out = []
        for (var i = 0; i < src.length; i++)
            if (q === "" || src[i].name.toLowerCase().indexOf(q) >= 0) out.push(src[i])
        return out
    }
    readonly property var crumbList: root.open && !root.recentMode ? root.crumbs(root.folder) : []
    property var sel: ({})                   // path → true
    property int cursor: -1
    property int anchor: -1

    // an in-card dropdown (file types, the app's options): a layer surface
    // that holds the keyboard cannot hand it to the shared ContextMenu's window
    property var dd: null                    // { options: [{id, label}], value, x, y, w, pick, from }
    property int ddIndex: 0                  // the option the arrow keys are on
    onDdChanged: {
        if (!root.dd) return
        var i = 0
        for (var k = 0; k < root.dd.options.length; k++) if (root.dd.options[k].id === root.dd.value) i = k
        root.ddIndex = i
    }
    function ddKey(ev) {
        var d = root.dd
        if (!d) return
        if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Tab) {
            root.dd = null
            if (d.from) d.from.forceActiveFocus()
        } else if (ev.key === Qt.Key_Up) { root.ddIndex = Math.max(0, root.ddIndex - 1)
        } else if (ev.key === Qt.Key_Down) { root.ddIndex = Math.min(d.options.length - 1, root.ddIndex + 1)
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { root.ddPick(root.ddIndex)
        } else return
        ev.accepted = true
    }
    function ddPick(i) {
        var d = root.dd
        if (!d || i < 0 || i >= d.options.length) return
        root.dd = null
        d.pick(d.options[i].id)
        if (d.from) d.from.forceActiveFocus()
    }

    // ── IPC (public API — Rule 4) ───────────────────────────────────────────
    IpcHandler {
        target: "filepicker"
        function open(path: string): string { return root.load(path) }
        function close(id: string): string {
            if (root.req && root.req.id === id) root.finish()
            return "ok"
        }
        function ping(id: string): string {
            if (!root.req) return "idle"
            return root.req.id === id ? "open" : "unknown"
        }
        function select(answer: string): string {
            if (!root.req) return "idle"
            var a
            try { a = JSON.parse(answer) } catch (e) { return "error: not JSON" }
            root.send(a)
            return "ok"
        }
        function cancel(): string { root.cancel(); return "ok" }
    }

    FileView { id: reqFile; blockLoading: true; printErrors: false }

    function load(path) {
        reqFile.path = path
        var r = null
        try { r = JSON.parse(reqFile.text()) } catch (e) { r = null }
        reqFile.path = ""
        if (!r || !r.id || ["open", "folder", "save", "saves"].indexOf(r.kind) < 0) return "error: unreadable request"
        if (root.req) root.finish()          // ewe-portal queues; a stray one is replaced
        root.begin(r)
        return "ok"
    }

    function activeClass() {
        var t = Hyprland.activeToplevel
        var c = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : ""
        if (!c && t && t.wayland && t.wayland.appId) c = t.wayland.appId
        return c
    }

    function begin(r) {
        root.appCls = root.activeClass()
        root.view = r.view === "grid" ? "grid" : "list"
        root.showHidden = !!r.hidden
        root.sortKey = ["name", "modified", "size"].indexOf(r.sort) >= 0 ? r.sort : "name"
        root.sortDesc = root.sortKey !== "name"
        root.filterIdx = r.filter >= 0 ? r.filter : 0
        var cv = {}
        for (var i = 0; i < (r.choices || []).length; i++) cv[r.choices[i].id] = r.choices[i].value
        root.choiceValues = cv
        root.search = ""; root.confirm = ""; root.error = ""; root.busy = false
        root.editingPath = false; root.makingFolder = false; root.dd = null
        root.back = []; root.fwd = []
        root.entries = []
        root.saveName = r.current_name || (r.current_file ? root.baseName(r.current_file) : "")
        var key = r.app_id || root.appCls
        var start = r.current_folder || (r.current_file ? root.dirName(r.current_file) : "")
                    || (r.remembered && key && r.remembered[key]) || r.home
        root.recentMode = false
        root.folder = start
        root.pendingSelect = r.current_file || ""
        root.clearSel()
        root.req = r
    }

    function finish() {
        root.req = null
        root.entries = []
        root.sel = ({})
        root.busy = false
        root.dd = null
    }

    // ── answering ───────────────────────────────────────────────────────────
    Process {
        id: answerProc
        stdout: StdioCollector { onStreamFinished: root.answered(this.text.trim()) }
        onExited: (code, status) => { if (code !== 0 && root.busy) root.answered("") }
    }
    function busArgs(id, json) {
        return ["busctl", "--user", "call", "org.freedesktop.impl.portal.desktop.ewe", "/org/ewe/Portal",
                "org.ewe.Portal1", "Answer", "ss", id, json]
    }
    function send(obj) {
        if (!root.req || root.busy) return
        if (!obj || !obj.ok) { root.cancel(); return }
        root.busy = true
        root.error = ""
        answerProc.command = root.busArgs(root.req.id, JSON.stringify(obj))
        answerProc.running = true
    }
    function answered(out) {
        if (!root.busy) return
        root.busy = false
        if (out === "b true") root.finish()
        else root.error = root.saving ? "Couldn’t save there. Pick another folder or name."
                                      : "Couldn’t use that. Pick another one."
    }
    function cancel() {
        if (!root.req) return
        Quickshell.execDetached(root.busArgs(root.req.id, JSON.stringify({ ok: false })))
        root.finish()
    }
    function remembered(folderPath) {
        return { key: root.rememberKey, folder: folderPath, view: root.view, hidden: root.showHidden, sort: root.sortKey }
    }
    function answerPaths(paths, folderPath) {
        root.send({ ok: true, paths: paths, choices: root.choiceValues, filter: root.filterIdx,
                    remember: root.remembered(folderPath) })
    }

    // the primary action
    function accept() {
        if (!root.req || root.busy) return
        if (root.saving) { root.trySave(); return }
        if (root.kind === "saves") { root.trySaveAll(); return }
        var picked = root.selectedEntries()
        if (root.kind === "folder") {
            if (root.recentMode) return
            var dirs = picked.filter(function (e) { return e.dir })
            root.answerPaths(dirs.length > 0 ? [dirs[0].path] : [root.folder], root.folder)
            return
        }
        var files = picked.filter(function (e) { return !e.dir })
        if (files.length === 0) {
            if (picked.length === 1 && picked[0].dir) root.navigate(picked[0].path)
            return
        }
        root.answerPaths(files.map(function (e) { return e.path }), root.dirName(files[0].path))
    }
    function trySave() {
        var name = root.saveName.trim()
        if (name === "") { root.error = "Type a name for the file."; return }
        var target = name.charAt(0) === "/" ? name
                   : name.indexOf("~/") === 0 ? root.home + name.substring(1)
                   : root.joinPath(root.folder, name)
        for (var i = 0; i < root.entries.length; i++) {
            if (root.entries[i].path !== target) continue
            if (root.entries[i].dir) { root.navigate(target); root.saveName = ""; return }
            if (root.confirm === "") {
                root.confirm = "“" + root.baseName(target) + "” already exists. Replace it?"
                return
            }
        }
        root.confirm = ""
        root.answerPaths([target], root.dirName(target))
    }
    function trySaveAll() {
        var names = root.req.files || [], clash = 0
        for (var i = 0; i < root.entries.length; i++)
            if (names.indexOf(root.entries[i].name) >= 0) clash++
        if (clash > 0 && root.confirm === "") {
            root.confirm = clash === 1 ? "A file with the same name is already here. Replace it?"
                                       : clash + " files with the same names are already here. Replace them?"
            return
        }
        root.confirm = ""
        root.send({ ok: true, folder: root.folder, choices: root.choiceValues, remember: root.remembered(root.folder) })
    }

    readonly property string primaryLabel: {
        if (root.confirm !== "") return "Replace"
        var a = root.req && root.req.accept_label ? root.stripMnemonic(root.req.accept_label) : ""
        if (a !== "") return a
        if (root.kind === "folder") return "Select folder"
        if (root.kind === "save") return "Save"
        if (root.kind === "saves") return "Save here"
        var n = root.selectedEntries().filter(function (e) { return !e.dir }).length
        return n > 1 ? "Open " + n + " files" : "Open"
    }
    readonly property bool primaryEnabled: {
        if (!root.req || root.busy) return false
        if (root.saving) return root.saveName.trim() !== ""
        if (root.pickFolder) return !root.recentMode
        var picked = root.selectedEntries()
        return picked.some(function (e) { return !e.dir }) || (picked.length === 1 && picked[0].dir)
    }
    readonly property string titleText: {
        var t = root.req && root.req.title ? root.stripMnemonic(root.req.title) : ""
        if (t !== "") return t
        return root.kind === "folder" ? "Select a folder" : root.kind === "save" ? "Save as"
             : root.kind === "saves" ? "Save files" : root.multiple ? "Open files" : "Open a file"
    }

    // ── navigation ──────────────────────────────────────────────────────────
    readonly property string recentMark: "\u0000recent"
    function here() { return root.recentMode ? root.recentMark : root.folder }
    function navigate(path, keepHistory) {
        if (path === "" || (!root.recentMode && path === root.folder)) return
        if (keepHistory !== false) { root.back = root.back.concat([root.here()]); root.fwd = [] }
        root.jump(path)
    }
    function showRecent() {
        if (root.recentMode) return
        root.back = root.back.concat([root.folder]); root.fwd = []
        root.jump(root.recentMark)
    }
    function goBack() {
        if (root.back.length === 0) return
        var p = root.back[root.back.length - 1]
        root.back = root.back.slice(0, -1)
        root.fwd = root.fwd.concat([root.here()])
        root.jump(p)
    }
    function goForward() {
        if (root.fwd.length === 0) return
        var p = root.fwd[root.fwd.length - 1]
        root.fwd = root.fwd.slice(0, -1)
        root.back = root.back.concat([root.here()])
        root.jump(p)
    }
    function jump(p) {
        if (p === root.recentMark) root.recentMode = true
        else { root.recentMode = false; root.folder = p }
        root.search = ""; root.confirm = ""; root.error = ""
        root.editingPath = false; root.makingFolder = false; root.dd = null
        root.pendingSelect = ""
        root.clearSel()
    }
    function goUp() {
        if (root.recentMode || root.folder === "/") return
        var child = root.folder
        root.navigate(root.dirName(root.folder))
        root.pendingSelect = child
    }
    function goTo(t) {
        var p = root.expandPath(t)
        if (root.saving && t.slice(-1) !== "/") {
            for (var i = 0; i < root.entries.length; i++)
                if (root.entries[i].path === p && root.entries[i].dir) { root.navigate(p); return }
            root.navigate(root.dirName(p)); root.saveName = root.baseName(p); return
        }
        root.navigate(p)
    }

    // ── selection ───────────────────────────────────────────────────────────
    function clearSel() { root.sel = ({}); root.cursor = -1; root.anchor = -1 }
    function selectable(e) { return root.pickFolder ? e.dir : true }
    function selectedEntries() {
        var out = []
        for (var i = 0; i < root.shown.length; i++) if (root.sel[root.shown[i].path]) out.push(root.shown[i])
        return out
    }
    function pick(i, mods) {
        if (i < 0 || i >= root.shown.length) return
        var e = root.shown[i]
        root.confirm = ""
        var s = {}
        if (root.multiple && (mods & Qt.ShiftModifier) && root.anchor >= 0) {
            var a = Math.min(root.anchor, i), b = Math.max(root.anchor, i)
            for (var k = a; k <= b; k++) if (!root.shown[k].dir) s[root.shown[k].path] = true
        } else if (root.multiple && (mods & Qt.ControlModifier)) {
            for (var p in root.sel) s[p] = true
            if (s[e.path]) delete s[e.path]; else s[e.path] = true
            root.anchor = i
        } else {
            if (root.selectable(e)) s[e.path] = true
            root.anchor = i
        }
        root.sel = s
        root.cursor = i
        if (root.saving && !e.dir) root.saveName = e.name
    }
    function activate(i) {
        if (i < 0 || i >= root.shown.length) return
        var e = root.shown[i]
        if (e.dir) { root.navigate(e.path); return }
        if (root.pickFolder) return
        if (root.saving) { root.saveName = e.name; root.trySave(); return }
        var s = {}; s[e.path] = true; root.sel = s; root.cursor = i
        root.accept()
    }
    function enter() {
        if (root.confirm !== "") { root.accept(); return }
        var cur = root.cursor >= 0 ? root.shown[root.cursor] : null
        var files = root.selectedEntries().filter(function (e) { return !e.dir })
        if (cur && cur.dir && files.length === 0) root.activate(root.cursor)
        else root.accept()
    }
    function moveCursor(d, mods) {
        var n = root.shown.length
        if (n === 0) return
        var i = root.cursor < 0 ? (d > 0 ? 0 : n - 1) : Math.max(0, Math.min(n - 1, root.cursor + d))
        root.pick(i, mods & Qt.ShiftModifier ? Qt.ShiftModifier : 0)
    }
    function selectAll() {
        if (!root.multiple) return
        var s = {}
        for (var i = 0; i < root.shown.length; i++) if (!root.shown[i].dir) s[root.shown[i].path] = true
        root.sel = s
    }
    property string typed: ""
    Timer { id: typedReset; interval: 1000; onTriggered: root.typed = "" }
    function typeAhead(ch) {
        root.typed += ch.toLowerCase()
        typedReset.restart()
        for (var i = 0; i < root.shown.length; i++)
            if (root.shown[i].name.toLowerCase().indexOf(root.typed) === 0) { root.pick(i, 0); return }
    }

    // ── the app's options ───────────────────────────────────────────────────
    function setChoice(id, value) {
        var v = {}
        for (var k in root.choiceValues) v[k] = root.choiceValues[k]
        v[id] = value
        root.choiceValues = v
    }
    function toggleChoice(id) { root.setChoice(id, root.choiceValues[id] === "true" ? "false" : "true") }
    function optionLabel(c, value) {
        for (var i = 0; i < c.options.length; i++) if (c.options[i].id === value) return c.options[i].label
        return ""
    }

    // ── new folder ──────────────────────────────────────────────────────────
    Process {
        id: mkdirProc
        property string made: ""
        onExited: (code, status) => {
            if (code === 0) root.navigate(mkdirProc.made)
            else root.error = "Couldn’t create that folder."
        }
    }
    function makeFolder(name) {
        var n = String(name).trim()
        if (n === "") return
        if (n.indexOf("/") >= 0 || n === "." || n === "..") { root.error = "A folder name can’t contain “/”."; return }
        mkdirProc.made = root.joinPath(root.folder, n)
        mkdirProc.command = ["mkdir", "--", mkdirProc.made]
        mkdirProc.running = true
    }

    // ── helpers ─────────────────────────────────────────────────────────────
    function stripMnemonic(s) { return String(s).replace(/_(_?)/g, function (m, u) { return u ? "_" : "" }) }
    function baseName(p) { var s = String(p).replace(/\/+$/, ""); return s.substring(s.lastIndexOf("/") + 1) || "/" }
    function dirName(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i <= 0 ? "/" : s.substring(0, i) }
    function joinPath(d, n) { return d === "/" ? "/" + n : d + "/" + n }
    function toUrl(p) { return "file://" + String(p).split("/").map(encodeURIComponent).join("/") }
    function prettyDir(p) {
        return p === root.home ? "Home" : p.indexOf(root.home + "/") === 0 ? "~" + p.substring(root.home.length) : p
    }
    function expandPath(t) {
        var s = String(t).trim()
        if (s === "~") return root.home
        if (s.indexOf("~/") === 0) s = root.home + s.substring(1)
        else if (s.charAt(0) !== "/") s = root.joinPath(root.folder, s)
        return s.length > 1 ? s.replace(/\/+$/, "") : s
    }
    function globRegex(gl) {
        if (!gl || gl.length === 0 || gl.indexOf("*") >= 0) return null
        var parts = gl.map(function (g) {
            var r = ""
            for (var i = 0; i < g.length; i++) {
                var c = g.charAt(i)
                if (c === "*") r += ".*"
                else if (c === "?") r += "."
                else if (c === "[") {
                    var j = g.indexOf("]", i)
                    if (j > i) { r += g.substring(i, j + 1); i = j } else r += "\\["
                } else r += c.replace(/[.+^${}()|\\\/]/g, "\\$&")
            }
            return r
        })
        return new RegExp("^(?:" + parts.join("|") + ")$", "i")
    }
    function suffix(name) { var i = name.lastIndexOf("."); return i > 0 ? name.substring(i + 1).toLowerCase() : "" }
    function glyphFor(e) {
        if (e.dir) return Theme.icFolder
        var x = root.suffix(e.name)
        if (["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "heif", "bmp", "tif", "tiff", "ico", "jxl"].indexOf(x) >= 0) return Theme.icImage
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg"].indexOf(x) >= 0) return Theme.icVideo
        if (["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "wma", "aiff"].indexOf(x) >= 0) return Theme.icMusic
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2", "tgz", "lz4"].indexOf(x) >= 0) return Theme.icArchive
        if (["js", "ts", "py", "rs", "c", "h", "cpp", "hpp", "go", "java", "qml", "sh", "json", "toml", "yaml", "yml",
             "lua", "css", "html", "xml", "kt", "swift", "rb", "php"].indexOf(x) >= 0) return Theme.icFileCode
        if (["txt", "md", "pdf", "doc", "docx", "odt", "rtf", "epub", "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp"].indexOf(x) >= 0) return Theme.icFileText
        return Theme.icFile
    }
    function isPicture(e) {
        return !e.dir && ["png", "jpg", "jpeg", "gif", "webp", "bmp", "avif", "svg"].indexOf(root.suffix(e.name)) >= 0
    }
    function sizeText(e) {
        if (e.dir || e.size < 0) return ""
        var b = e.size
        if (b < 1000) return b + " B"
        var u = ["KB", "MB", "GB", "TB"], v = b / 1000, k = 0
        while (v >= 1000 && k < u.length - 1) { v /= 1000; k++ }
        return (v < 10 ? v.toFixed(1) : Math.round(v)) + " " + u[k]
    }
    function dateText(d) {
        if (!d || isNaN(d.getTime())) return ""
        var now = new Date()
        var day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        if (day === today) return Globals.formatTime(d, false)
        if (day === today - 86400000) return "Yesterday"
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    function appName(cls) {
        var e = cls ? Globals.entryForClass(cls) : null
        if (e && e.name) return e.name
        if (!cls) return ""
        var w = String(cls).split(/[.\-_ ]/).filter(function (x) { return x !== "" })
        var s = w.length > 0 ? w[w.length - 1] : String(cls)
        return s.charAt(0).toUpperCase() + s.substring(1)
    }
    function placeGlyph(icon) {
        return ({ home: Theme.icHome, desktop: Theme.icComputer, documents: Theme.icFileText, downloads: Theme.icDownload,
                  music: Theme.icMusic, pictures: Theme.icImage, videos: Theme.icVideo, cloud: Theme.icCloud,
                  pin: Theme.icPin, drive: Theme.icDrive })[icon] || Theme.icFolder
    }
    function crumbs(p) {
        var out = []
        if (p === root.home || p.indexOf(root.home + "/") === 0) {
            out.push({ label: "Home", path: root.home })
            var rest = p.substring(root.home.length).split("/").filter(function (x) { return x !== "" }), acc = root.home
            for (var i = 0; i < rest.length; i++) { acc += "/" + rest[i]; out.push({ label: rest[i], path: acc }) }
        } else {
            out.push({ label: "/", path: "/" })
            var segs = p.split("/").filter(function (x) { return x !== "" }), a2 = ""
            for (var j = 0; j < segs.length; j++) { a2 += "/" + segs[j]; out.push({ label: segs[j], path: a2 }) }
        }
        return out
    }

    // a Select's closed state: the value and a chevron (design system: Select)
    component DropButton: Rectangle {
        id: db
        property string text: ""
        signal openAt(real x, real y, real w)
        width: Math.min(dbTxt.implicitWidth, Theme.panelSm / 2) + Theme.iconSm + 3 * Theme.spaceS
        height: Theme.controlMd
        radius: Theme.radiusPrimary
        color: dbMa.pressed ? Theme.surfacePressed : dbMa.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
        border.color: db.activeFocus ? Theme.focusRing : Theme.borderStrong
        border.width: Theme.borderWidth1
        activeFocusOnTab: true
        Keys.onSpacePressed: db.fire()
        Keys.onReturnPressed: db.fire()
        Keys.onDownPressed: db.fire()
        function fire() {
            var card = db.parent
            while (card && card.objectName !== "filePickerCard") card = card.parent
            var p = card ? db.mapToItem(card, 0, 0) : Qt.point(0, 0)
            db.openAt(p.x, p.y, db.width)
        }
        TextBody {
            id: dbTxt
            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
            anchors.right: dbChev.left; anchors.rightMargin: Theme.spaceXs
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: db.text
        }
        Text {
            id: dbChev
            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.icChevronDown
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
            color: Theme.textSecondary
        }
        MouseArea {
            id: dbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { db.forceActiveFocus(); db.fire() }
        }
    }

    // a sortable column title (list view)
    component SortHead: Rectangle {
        id: sh
        property string key
        property string label
        property bool alignRight: false
        height: Theme.controlSm
        radius: Theme.radiusSlight
        color: shMa.containsMouse ? Theme.surfaceHover : "transparent"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: sh.alignRight ? undefined : parent.left
            anchors.right: sh.alignRight ? parent.right : undefined
            anchors.leftMargin: Theme.spaceS
            anchors.rightMargin: Theme.spaceS
            spacing: Theme.spaceXxs
            TextCaption { text: sh.label; color: root.sortKey === sh.key ? Theme.textPrimary : Theme.textMuted }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.sortKey === sh.key
                text: root.sortDesc ? Theme.icChevronDown : Theme.icChevronUp
                font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
                color: Theme.textMuted
            }
        }
        MouseArea {
            id: shMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sortKey === sh.key) root.sortDesc = !root.sortDesc
                else { root.sortKey = sh.key; root.sortDesc = sh.key !== "name" }
            }
        }
    }

    // ── the surface ─────────────────────────────────────────────────────────
    LazyLoader {
        active: root.open
        PanelWindow {
            id: win
            screen: {
                var s = Quickshell.screens, fm = Hyprland.focusedMonitor
                if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
                return s.length > 0 ? s[0] : null
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:file-picker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { top: true; bottom: true; left: true; right: true }

            // focus lands once the surface is mapped (a forceActiveFocus at
            // creation is lost to the keyboard arriving) — the Share picker's way
            onVisibleChanged: if (visible) focusIn.restart()
            Component.onCompleted: focusIn.restart()
            Timer {
                id: focusIn
                interval: 0
                onTriggered: {
                    if (!root.saving) { keys.forceActiveFocus(); return }
                    nameInput.forceActiveFocus()
                    var dot = nameInput.text.lastIndexOf(".")
                    nameInput.select(0, dot > 0 ? dot : nameInput.text.length)
                }
            }

            FolderListModel {
                id: fs
                folder: root.toUrl(root.folder)
                showDirs: true
                showFiles: root.kind !== "folder"
                showDirsFirst: true
                showDotAndDotDot: false
                showHidden: root.showHidden
                sortCaseSensitive: false
                caseSensitive: false
                nameFilters: root.globs
                sortField: root.sortKey === "modified" ? FolderListModel.Time
                         : root.sortKey === "size" ? FolderListModel.Size : FolderListModel.Name
                sortReversed: root.sortDesc
                onStatusChanged: rebuild.restart()
                onCountChanged: rebuild.restart()
                onFolderChanged: { root.loading = true; root.entries = []; rebuild.restart() }
            }
            Timer {
                id: rebuild
                interval: 0
                onTriggered: {
                    var out = []
                    for (var i = 0; i < fs.count; i++)
                        out.push({ name: fs.get(i, "fileName"), path: fs.get(i, "filePath"), dir: fs.get(i, "fileIsDir"),
                                   size: fs.get(i, "fileSize"), mtime: fs.get(i, "fileModified"), where: "" })
                    root.entries = out
                    root.loading = fs.status === FolderListModel.Loading
                    if (root.pendingSelect !== "" && !root.recentMode) {
                        for (var k = 0; k < root.shown.length; k++)
                            if (root.shown[k].path === root.pendingSelect) { root.pick(k, 0); break }
                        if (fs.status === FolderListModel.Ready) root.pendingSelect = ""
                    }
                }
            }

            Rectangle { anchors.fill: parent; color: Theme.scrim }
            MouseArea { anchors.fill: parent }   // the scrim does nothing (Dialog)

            Rectangle {
                id: card
                objectName: "filePickerCard"
                anchors.centerIn: parent
                width: Math.min(Theme.panelLg + Theme.panelSm - Theme.spaceLg - Theme.spaceS,
                                parent.width - 2 * (Theme.spaceXl + Theme.spaceMd))
                height: Math.min(Theme.panelLg + Theme.spaceXl, parent.height - 2 * (Theme.spaceXl + Theme.spaceMd))
                radius: Theme.radiusRounded
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                layer.enabled: true
                layer.effect: Elevation {}
                MouseArea { anchors.fill: parent; onClicked: { root.dd = null; keys.forceActiveFocus() } }

                // keyboard: the list's keys live here; fields take their own
                Item {
                    id: keys
                    anchors.fill: parent
                    focus: true
                    activeFocusOnTab: true
                    Keys.onPressed: (ev) => keys.handle(ev)
                    function handle(ev) {
                        var ctrl = ev.modifiers & Qt.ControlModifier, alt = ev.modifiers & Qt.AltModifier
                        if (ev.key === Qt.Key_Escape) {
                            if (root.confirm !== "") root.confirm = ""
                            else root.cancel()
                        } else if (ctrl && ev.key === Qt.Key_L) { root.editingPath = true
                        } else if (ctrl && ev.key === Qt.Key_F) { searchInput.forceActiveFocus()
                        } else if (ctrl && ev.key === Qt.Key_H) { root.showHidden = !root.showHidden
                        } else if (ctrl && ev.key === Qt.Key_A) { root.selectAll()
                        } else if (alt && ev.key === Qt.Key_Left) { root.goBack()
                        } else if (alt && ev.key === Qt.Key_Right) { root.goForward()
                        } else if ((alt && ev.key === Qt.Key_Up) || ev.key === Qt.Key_Backspace) { root.goUp()
                        } else if (ev.key === Qt.Key_Down) { root.moveCursor(root.view === "grid" ? grid.columns : 1, ev.modifiers)
                        } else if (ev.key === Qt.Key_Up) { root.moveCursor(root.view === "grid" ? -grid.columns : -1, ev.modifiers)
                        } else if (ev.key === Qt.Key_Right && root.view === "grid") { root.moveCursor(1, ev.modifiers)
                        } else if (ev.key === Qt.Key_Left && root.view === "grid") { root.moveCursor(-1, ev.modifiers)
                        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.enter()
                        } else if (ev.text === "/" || ev.text === "~") {
                            pathInput.text = ev.text === "~" ? "~/" : "/"
                            root.editingPath = true
                        } else if (ev.text.length === 1 && ev.text > " " && !ctrl && !alt) {
                            root.typeAhead(ev.text)
                        } else return
                        ev.accepted = true
                    }
                }
                // an open dropdown takes the keys from whoever opened it
                Item {
                    id: ddKeys
                    Keys.onPressed: (ev) => root.ddKey(ev)
                    Connections {
                        target: root
                        function onDdChanged() { if (root.dd) ddKeys.forceActiveFocus() }
                    }
                }

                Column {
                    id: body
                    anchors.fill: parent
                    anchors.margins: Theme.spaceMd
                    spacing: Theme.spaceMd

                    // ── header: who asked, what for ──
                    Item {
                        id: head
                        width: parent.width
                        height: Math.max(titleCol.implicitHeight, Theme.controlMd)
                        Image {
                            id: appIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: visible ? Theme.iconXl : 0
                            height: Theme.iconXl
                            sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl
                            mipmap: true
                            source: root.appCls !== "" ? Globals.iconForClass(root.appCls) : ""
                            visible: String(source) !== "" && status !== Image.Error
                        }
                        Column {
                            id: titleCol
                            anchors.left: appIcon.right
                            anchors.leftMargin: appIcon.visible ? Theme.spaceS + Theme.spaceXs : 0
                            anchors.right: closeBtn.left
                            anchors.rightMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: root.titleText
                                color: Theme.textPrimary
                                font.family: Theme.type.h3.family
                                font.pixelSize: Theme.type.h3.size
                                font.weight: Theme.type.h3.weight
                                font.letterSpacing: Theme.type.h3.letterSpacing
                            }
                            TextCaption {
                                width: parent.width; elide: Text.ElideRight
                                visible: text !== ""
                                text: root.appName(root.appCls)
                            }
                        }
                        QsIconButton {
                            id: closeBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            ic: Theme.icClose; tip: "Cancel"
                            onGo: root.cancel()
                        }
                    }

                    // ── places | folder ──
                    Item {
                        id: middle
                        width: parent.width
                        height: body.height - head.height - foot.height - 2 * body.spacing
                                - (saveRow.visible ? saveRow.height + body.spacing : 0)
                                - (alertRow.visible ? alertRow.height + body.spacing : 0)

                        Flickable {
                            id: side
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: Theme.panelSm / 2
                            contentHeight: sideCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Column {
                                id: sideCol
                                width: parent.width
                                spacing: Theme.spaceXxs
                                ListRow {
                                    visible: root.kind === "open" && !!root.req && !!root.req.recent && root.req.recent.length > 0
                                    density: "dense"; glyph: Theme.icHistory; label: "Recent"
                                    activeFocusOnTab: false
                                    selected: root.recentMode
                                    onClicked: root.showRecent()
                                }
                                Repeater {
                                    model: ["places", "cloud", "pinned", "drives"]
                                    Column {
                                        id: grp
                                        required property string modelData
                                        readonly property var items: root.places.filter(function (p) { return p.group === grp.modelData })
                                        width: sideCol.width
                                        spacing: Theme.spaceXxs
                                        visible: grp.items.length > 0
                                        Text {
                                            visible: grp.modelData !== "places"
                                            topPadding: Theme.spaceS
                                            leftPadding: Theme.spaceS
                                            bottomPadding: Theme.spaceXxs
                                            text: ({ cloud: "Your account", pinned: "Pinned", drives: "Drives" })[grp.modelData] || ""
                                            color: Theme.textMuted
                                            font.family: Theme.type.overline.family
                                            font.pixelSize: Theme.type.overline.size
                                            font.weight: Theme.type.overline.weight
                                            font.letterSpacing: Theme.type.overline.letterSpacing
                                        }
                                        Repeater {
                                            model: grp.items
                                            ListRow {
                                                required property var modelData
                                                width: grp.width
                                                density: "dense"
                                                activeFocusOnTab: false   // Tab: list → search → footer
                                                glyph: root.placeGlyph(modelData.icon)
                                                label: modelData.name
                                                selected: !root.recentMode && root.folder === modelData.path
                                                onClicked: root.navigate(modelData.path)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            id: sideRule
                            anchors { left: side.right; leftMargin: Theme.spaceS + Theme.spaceXs; top: parent.top; bottom: parent.bottom }
                            width: Theme.borderWidth1
                            color: Theme.borderSubtle
                        }

                        Item {
                            id: main
                            anchors { left: sideRule.right; leftMargin: Theme.spaceS + Theme.spaceXs; right: parent.right
                                      top: parent.top; bottom: parent.bottom }

                            // ── toolbar ──
                            Item {
                                id: bar
                                width: parent.width
                                height: Theme.controlMd
                                Row {
                                    id: navBtns
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spaceXxs
                                    // nowhere to go: the glyph in textDisabled (Icon button, disabled)
                                    QsIconButton {
                                        size: "md"; ic: Theme.icBack; tip: "Back"
                                        glyph: root.back.length > 0 ? Theme.textSecondary : Theme.textDisabled
                                        onGo: root.goBack()
                                    }
                                    QsIconButton {
                                        size: "md"; ic: Theme.icForward; tip: "Forward"
                                        glyph: root.fwd.length > 0 ? Theme.textSecondary : Theme.textDisabled
                                        onGo: root.goForward()
                                    }
                                    QsIconButton {
                                        size: "md"; ic: Theme.icArrowUp; tip: "Up a folder"
                                        glyph: !root.recentMode && root.folder !== "/" ? Theme.textSecondary : Theme.textDisabled
                                        onGo: root.goUp()
                                    }
                                }
                                Row {
                                    id: tools
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spaceXxs
                                    QsField {
                                        width: Theme.panelSm / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        focused: searchInput.activeFocus
                                        Text {
                                            id: searchGlyph
                                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Theme.icSearch
                                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                            color: Theme.textMuted
                                        }
                                        QsFieldInput {
                                            id: searchInput
                                            anchors { left: searchGlyph.right; leftMargin: Theme.spaceXs; right: parent.right
                                                      rightMargin: Theme.spaceS; top: parent.top; bottom: parent.bottom }
                                            placeholder: root.recentMode ? "Search recent" : "Search this folder"
                                            text: root.search
                                            onTextEdited: { root.search = text; root.cursor = -1 }
                                            Keys.onEscapePressed: { root.search = ""; keys.forceActiveFocus() }
                                            Keys.onDownPressed: { keys.forceActiveFocus(); root.moveCursor(1, 0) }
                                            Keys.onReturnPressed: { keys.forceActiveFocus(); if (root.shown.length > 0) root.pick(0, 0) }
                                        }
                                    }
                                    QsIconButton {
                                        size: "md"; ic: Theme.icFolderPlus; tip: "New folder"
                                        visible: root.kind !== "open" && !root.recentMode
                                        onGo: { root.editingPath = false; root.makingFolder = true }
                                    }
                                    QsIconButton {
                                        size: "md"; ic: root.showHidden ? Theme.icEye : Theme.icEyeOff
                                        tip: root.showHidden ? "Hide hidden files" : "Show hidden files"
                                        selected: root.showHidden
                                        onGo: root.showHidden = !root.showHidden
                                    }
                                    QsIconButton {
                                        size: "md"; ic: root.view === "grid" ? Theme.icList : Theme.icGrid
                                        tip: root.view === "grid" ? "Show as a list" : "Show as a grid"
                                        onGo: root.view = root.view === "grid" ? "list" : "grid"
                                    }
                                }

                                // the breadcrumb, or a path / new-folder field in its place
                                Item {
                                    id: crumbArea
                                    anchors { left: navBtns.right; leftMargin: Theme.spaceS; right: tools.left; rightMargin: Theme.spaceS
                                              verticalCenter: parent.verticalCenter }
                                    height: Theme.controlMd
                                    clip: true
                                    TextStrong {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: root.recentMode && !root.editingPath
                                        text: "Recent"
                                    }
                                    Flickable {
                                        anchors.fill: parent
                                        visible: !root.recentMode && !root.editingPath && !root.makingFolder
                                        contentWidth: crumbRow.implicitWidth
                                        contentX: Math.max(0, contentWidth - width)
                                        interactive: contentWidth > width
                                        boundsBehavior: Flickable.StopAtBounds
                                        Row {
                                            id: crumbRow
                                            height: parent.height
                                            spacing: Theme.spaceXxs
                                            Repeater {
                                                model: root.crumbList
                                                Row {
                                                    id: crumb
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool last: crumb.index === root.crumbList.length - 1
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: Theme.spaceXxs
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: crumb.index > 0
                                                        text: Theme.icChevronRight
                                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                                        color: Theme.textMuted
                                                    }
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: crumbTxt.implicitWidth + 2 * Theme.spaceXs
                                                        height: crumbTxt.implicitHeight + 2 * Theme.spaceXxs
                                                        radius: Theme.radiusSlight
                                                        color: crumbMa.containsMouse && !crumb.last ? Theme.surfaceHover : "transparent"
                                                        Text {
                                                            id: crumbTxt
                                                            anchors.centerIn: parent
                                                            text: crumb.modelData.label
                                                            color: crumb.last || crumbMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                                            font.family: Theme.type.label.family
                                                            font.pixelSize: Theme.fontSizeS
                                                            font.weight: crumb.last ? Theme.fontWeightMedium : Theme.fontWeightRegular
                                                        }
                                                        MouseArea {
                                                            id: crumbMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: crumb.last ? Qt.IBeamCursor : Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (!crumb.last) root.navigate(crumb.modelData.path)
                                                                else root.editingPath = true
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    QsField {
                                        anchors.fill: parent
                                        visible: root.editingPath || root.makingFolder
                                        focused: pathInput.activeFocus
                                        QsFieldInput {
                                            id: pathInput
                                            anchors { fill: parent; leftMargin: Theme.spaceS; rightMargin: Theme.spaceS }
                                            placeholder: root.makingFolder ? "Name of the new folder" : "Type a path"
                                            onVisibleChanged: if (visible) {
                                                if (root.makingFolder) text = ""
                                                else if (text === "") text = (root.prettyDir(root.folder) === "Home" ? "~" : root.prettyDir(root.folder)) + "/"
                                                forceActiveFocus()
                                                cursorPosition = text.length
                                            }
                                            Keys.onEscapePressed: { root.editingPath = false; root.makingFolder = false; text = ""; keys.forceActiveFocus() }
                                            Keys.onReturnPressed: {
                                                var t = text.trim(), making = root.makingFolder
                                                text = ""
                                                root.editingPath = false; root.makingFolder = false
                                                keys.forceActiveFocus()
                                                if (making) root.makeFolder(t)
                                                else if (t !== "") root.goTo(t)
                                            }
                                            onActiveFocusChanged: if (!activeFocus && (root.editingPath || root.makingFolder)) {
                                                root.editingPath = false; root.makingFolder = false; text = ""
                                            }
                                        }
                                    }
                                }
                            }

                            // ── column header (list view) ──
                            Item {
                                id: colHead
                                anchors { top: bar.bottom; topMargin: Theme.spaceS; left: parent.left; right: parent.right
                                          leftMargin: Theme.spaceXs + Theme.borderWidth1; rightMargin: Theme.spaceXs + Theme.borderWidth1 }
                                height: visible ? Theme.controlSm : 0
                                visible: root.view === "list"
                                SortHead { anchors.left: parent.left; anchors.right: sizeHead.left; key: "name"; label: "Name" }
                                SortHead {
                                    id: sizeHead
                                    anchors.right: dateHead.left
                                    width: root.pickFolder ? 0 : Theme.panelSm / 4
                                    visible: !root.pickFolder
                                    key: "size"; label: "Size"; alignRight: true
                                }
                                SortHead { id: dateHead; anchors.right: parent.right; width: Theme.panelSm / 3; key: "modified"; label: "Modified"; alignRight: true }
                            }

                            // ── the listing ──
                            Rectangle {
                                id: well
                                anchors { top: colHead.bottom; topMargin: Theme.spaceXs; left: parent.left; right: parent.right; bottom: parent.bottom }
                                radius: Theme.radiusPrimary
                                color: Theme.surfaceSunken
                                border.color: Theme.borderSubtle
                                border.width: Theme.borderWidth1

                                ListView {
                                    id: list
                                    anchors.fill: parent
                                    anchors.margins: Theme.spaceXs
                                    visible: root.view === "list"
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: root.view === "list" ? root.shown : []
                                    currentIndex: root.cursor
                                    highlightFollowsCurrentItem: false
                                    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                                    delegate: Rectangle {
                                        id: rowD
                                        required property var modelData
                                        required property int index
                                        readonly property bool picked: !!root.sel[rowD.modelData.path]
                                        readonly property bool dim: root.pickFolder && !rowD.modelData.dir
                                        width: list.width
                                        height: Math.max(Theme.controlLg, rowText.implicitHeight + 2 * Theme.spaceXs)
                                        radius: Theme.radiusSecondary
                                        color: rowD.picked ? Theme.accentSubtle : rowMa.containsMouse ? Theme.surfaceHover : "transparent"
                                        border.color: root.cursor === rowD.index ? Theme.focusRing : "transparent"
                                        border.width: root.cursor === rowD.index ? Theme.focusWidth : 0
                                        Text {
                                            id: rowGlyph
                                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.glyphFor(rowD.modelData)
                                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                            color: rowD.dim ? Theme.textDisabled : rowD.modelData.dir ? Theme.accentText : Theme.textSecondary
                                        }
                                        Column {
                                            id: rowText
                                            anchors { left: rowGlyph.right; leftMargin: Theme.spaceS; right: rowSize.left; rightMargin: Theme.spaceS
                                                      verticalCenter: parent.verticalCenter }
                                            TextBody {
                                                width: parent.width
                                                elide: Text.ElideMiddle
                                                text: rowD.modelData.name
                                                color: rowD.dim ? Theme.textDisabled : Theme.textPrimary
                                            }
                                            TextCaption {
                                                width: parent.width
                                                visible: rowD.modelData.where !== ""
                                                elide: Text.ElideMiddle
                                                text: rowD.modelData.where
                                            }
                                        }
                                        TextCaption {
                                            id: rowSize
                                            anchors.right: rowDate.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: root.pickFolder ? 0 : Theme.panelSm / 4 - Theme.spaceS
                                            horizontalAlignment: Text.AlignRight
                                            text: root.sizeText(rowD.modelData)
                                        }
                                        TextCaption {
                                            id: rowDate
                                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Theme.panelSm / 3 - Theme.spaceS
                                            horizontalAlignment: Text.AlignRight
                                            text: root.dateText(rowD.modelData.mtime)
                                        }
                                        MouseArea {
                                            id: rowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: (m) => { keys.forceActiveFocus(); root.dd = null; root.pick(rowD.index, m.modifiers) }
                                            onDoubleClicked: root.activate(rowD.index)
                                        }
                                    }
                                }

                                GridView {
                                    id: grid
                                    readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
                                    anchors.fill: parent
                                    anchors.margins: Theme.spaceXs
                                    visible: root.view === "grid"
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    cellWidth: 2 * Theme.control2xl + Theme.spaceMd
                                    cellHeight: 2 * Theme.control2xl + Theme.spaceMd
                                    model: root.view === "grid" ? root.shown : []
                                    currentIndex: root.cursor
                                    highlightFollowsCurrentItem: false
                                    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
                                    delegate: Item {
                                        id: cellD
                                        required property var modelData
                                        required property int index
                                        readonly property bool picked: !!root.sel[cellD.modelData.path]
                                        readonly property bool dim: root.pickFolder && !cellD.modelData.dir
                                        width: grid.cellWidth
                                        height: grid.cellHeight
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spaceXxs
                                            radius: Theme.radiusPrimary
                                            color: cellD.picked ? Theme.accentSubtle : cellMa.containsMouse ? Theme.surfaceHover : "transparent"
                                            border.color: root.cursor === cellD.index ? Theme.focusRing : "transparent"
                                            border.width: root.cursor === cellD.index ? Theme.focusWidth : 0
                                        }
                                        Item {
                                            id: thumbBox
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                            width: Theme.icon4xl; height: Theme.icon4xl
                                            Text {
                                                anchors.centerIn: parent
                                                visible: thumb.status !== Image.Ready
                                                text: root.glyphFor(cellD.modelData)
                                                font.family: Theme.fontIcons; font.pixelSize: Theme.icon3xl
                                                color: cellD.dim ? Theme.textDisabled : cellD.modelData.dir ? Theme.accentText : Theme.textSecondary
                                            }
                                            Image {
                                                id: thumb
                                                anchors.fill: parent
                                                visible: status === Image.Ready
                                                asynchronous: true
                                                cache: false
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize.width: 2 * Theme.icon4xl; sourceSize.height: 2 * Theme.icon4xl
                                                source: root.isPicture(cellD.modelData) ? root.toUrl(cellD.modelData.path) : ""
                                            }
                                        }
                                        Text {
                                            anchors { top: thumbBox.bottom; topMargin: Theme.spaceXs; left: parent.left; right: parent.right
                                                      leftMargin: Theme.spaceXs; rightMargin: Theme.spaceXs }
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WrapAnywhere
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            text: cellD.modelData.name
                                            color: cellD.dim ? Theme.textDisabled : Theme.textPrimary
                                            font.family: Theme.type.caption.family
                                            font.pixelSize: Theme.type.caption.size
                                        }
                                        MouseArea {
                                            id: cellMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: (m) => { keys.forceActiveFocus(); root.dd = null; root.pick(cellD.index, m.modifiers) }
                                            onDoubleClicked: root.activate(cellD.index)
                                        }
                                    }
                                }

                                Spinner {
                                    anchors.centerIn: parent
                                    visible: root.loading && root.shown.length === 0 && !root.recentMode
                                }
                                QsEmpty {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width - 2 * Theme.spaceMd, Theme.panelSm)
                                    visible: !(root.loading && !root.recentMode) && root.shown.length === 0
                                    readonly property bool narrowed: root.globs.indexOf("*") < 0 && root.filters.length > 0
                                    ic: root.search !== "" ? Theme.icSearch : root.recentMode ? Theme.icHistory : Theme.icFolder
                                    title: root.search !== "" ? "No matches"
                                         : root.recentMode ? "Nothing recent"
                                         : narrowed ? "No matching files here"
                                         : "This folder is empty"
                                    desc: root.search !== "" ? "Nothing here has “" + root.search + "” in its name."
                                        : root.recentMode ? "Files you open show up here."
                                        : narrowed && root.filters.length > 1 ? "Pick another file type below, or another folder."
                                        : ""
                                }
                            }
                        }
                    }

                    // ── save: the name ──
                    Item {
                        id: saveRow
                        width: parent.width
                        height: visible ? Theme.controlMd : 0
                        visible: root.saving || root.kind === "saves"
                        TextStrong {
                            id: saveLabel
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.saving ? "Name" : "Saving"
                        }
                        QsField {
                            visible: root.saving
                            anchors { left: saveLabel.right; leftMargin: Theme.spaceS + Theme.spaceXs; right: parent.right
                                      verticalCenter: parent.verticalCenter }
                            focused: nameInput.activeFocus
                            error: root.error !== "" && root.saveName.trim() === ""
                            QsFieldInput {
                                id: nameInput
                                anchors { fill: parent; leftMargin: Theme.spaceS; rightMargin: Theme.spaceS }
                                placeholder: "File name"
                                text: root.saveName
                                onTextEdited: { root.saveName = text; root.confirm = ""; root.error = "" }
                                Keys.onReturnPressed: root.accept()
                                Keys.onEnterPressed: root.accept()
                                Keys.onEscapePressed: { if (root.confirm !== "") root.confirm = ""; else root.cancel() }
                                Keys.onDownPressed: { keys.forceActiveFocus(); root.moveCursor(1, 0) }
                            }
                        }
                        TextBody {
                            visible: root.kind === "saves"
                            anchors { left: saveLabel.right; leftMargin: Theme.spaceS + Theme.spaceXs; right: parent.right
                                      verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            color: Theme.textSecondary
                            text: root.req && root.req.files ? root.req.files.join(", ") : ""
                        }
                    }

                    // ── a question or a problem, above the footer ──
                    Item {
                        id: alertRow
                        width: parent.width
                        height: visible ? Theme.controlSm : 0
                        visible: root.confirm !== "" || root.error !== ""
                        Text {
                            id: alertGlyph
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icWarning
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: root.confirm !== "" ? Theme.warning : Theme.danger
                        }
                        TextBody {
                            anchors { left: alertGlyph.right; leftMargin: Theme.spaceS; right: parent.right; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: root.confirm !== "" ? root.confirm : root.error
                        }
                    }

                    // ── footer: file types, the app's options, Cancel, the action ──
                    Column {
                        id: foot
                        width: parent.width
                        spacing: Theme.spaceS + Theme.spaceXs
                        Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                        Item {
                            width: parent.width
                            height: Theme.controlMd
                            Item {
                                anchors { left: parent.left; right: actions.left; rightMargin: Theme.spaceMd; top: parent.top; bottom: parent.bottom }
                                clip: true
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spaceS + Theme.spaceXs
                                    DropButton {
                                        id: filterBtn
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: root.filters.length > 1
                                        text: root.filters.length > 0 && root.filterIdx < root.filters.length ? root.filters[root.filterIdx].name : ""
                                        onOpenAt: (x, y, w) => {
                                            root.dd = {
                                                options: root.filters.map(function (f, i) { return { id: String(i), label: f.name } }),
                                                value: String(root.filterIdx), x: x, y: y, w: w, from: filterBtn,
                                                pick: function (id) { root.filterIdx = parseInt(id); root.clearSel() }
                                            }
                                        }
                                    }
                                    TextCaption {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: root.filters.length === 1
                                        text: root.filters.length === 1 ? root.filters[0].name : ""
                                    }
                                    Repeater {
                                        model: root.choices
                                        Row {
                                            id: ch
                                            required property var modelData
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.spaceS
                                            // a checkbox (no options) — the Share picker's
                                            Rectangle {
                                                readonly property bool checked: root.choiceValues[ch.modelData.id] === "true"
                                                visible: ch.modelData.kind === "toggle"
                                                width: Theme.iconMd; height: Theme.iconMd
                                                radius: Theme.radiusSlight
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: checked ? Theme.accent : Theme.surfaceSunken
                                                border.color: checked ? Theme.accent : Theme.borderStrong
                                                border.width: Theme.borderWidth1
                                                activeFocusOnTab: visible
                                                Keys.onSpacePressed: root.toggleChoice(ch.modelData.id)
                                                Keys.onReturnPressed: root.toggleChoice(ch.modelData.id)
                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: -(parent.border.width + Theme.focusWidth)
                                                    radius: Theme.radiusSlight + Theme.focusWidth
                                                    color: "transparent"
                                                    visible: parent.activeFocus
                                                    border.color: Theme.focusRing; border.width: Theme.focusWidth
                                                }
                                                Text {
                                                    anchors.centerIn: parent; visible: parent.checked
                                                    text: Theme.icCheck
                                                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
                                                    color: Theme.onAccent
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleChoice(ch.modelData.id) }
                                            }
                                            TextBody {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ch.modelData.label
                                                color: Theme.textSecondary
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: ch.modelData.kind === "toggle"
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleChoice(ch.modelData.id)
                                                }
                                            }
                                            DropButton {
                                                id: chBtn
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: ch.modelData.kind === "select"
                                                text: root.optionLabel(ch.modelData, root.choiceValues[ch.modelData.id])
                                                onOpenAt: (x, y, w) => {
                                                    root.dd = {
                                                        options: ch.modelData.options, value: root.choiceValues[ch.modelData.id],
                                                        x: x, y: y, w: w, from: chBtn,
                                                        pick: function (id) { root.setChoice(ch.modelData.id, id) }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Row {
                                id: actions
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceS
                                QsButton { size: "md"; variant: "ghost"; label: "Cancel"; onGo: root.cancel() }
                                QsButton {
                                    size: "md"
                                    variant: root.confirm !== "" ? "danger" : "primary"
                                    label: root.primaryLabel
                                    disabled: !root.primaryEnabled
                                    busy: root.busy
                                    onGo: root.accept()
                                }
                            }
                        }
                    }
                }

                // the open dropdown, above everything in the card
                Rectangle {
                    id: ddBox
                    visible: root.dd !== null
                    x: root.dd ? Math.max(Theme.spaceS, Math.min(root.dd.x, card.width - width - Theme.spaceS)) : 0
                    y: root.dd ? Math.max(Theme.spaceS, root.dd.y - height - Theme.spaceXs) : 0
                    width: root.dd ? Math.max(root.dd.w, Theme.panelSm / 2) : 0
                    height: Math.min(ddCol.implicitHeight + 2 * Theme.spaceXs, card.height / 2)
                    radius: Theme.radiusRounded
                    color: Theme.surfaceOverlay
                    border.color: Theme.borderSubtle
                    border.width: Theme.borderWidth1
                    layer.enabled: visible
                    layer.effect: Elevation {}
                    MouseArea { anchors.fill: parent }
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.spaceXs
                        contentHeight: ddCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: ddCol
                            width: parent.width
                            Repeater {
                                model: root.dd ? root.dd.options : []
                                Rectangle {
                                    id: ddItem
                                    required property var modelData
                                    required property int index
                                    width: ddCol.width
                                    height: Theme.controlMd
                                    radius: Theme.radiusSecondary
                                    color: ddMa.containsMouse || root.ddIndex === ddItem.index ? Theme.surfaceHover : "transparent"
                                    border.color: root.ddIndex === ddItem.index ? Theme.focusRing : "transparent"
                                    border.width: root.ddIndex === ddItem.index ? Theme.focusWidth : 0
                                    Text {
                                        id: ddTick
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.iconMd
                                        text: root.dd && root.dd.value === ddItem.modelData.id ? Theme.icCheck : ""
                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                        color: Theme.accentText
                                    }
                                    TextBody {
                                        anchors { left: ddTick.right; leftMargin: Theme.spaceS; right: parent.right; rightMargin: Theme.spaceS
                                                  verticalCenter: parent.verticalCenter }
                                        elide: Text.ElideRight
                                        text: ddItem.modelData.label
                                    }
                                    MouseArea {
                                        id: ddMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.ddIndex = ddItem.index
                                        onClicked: root.ddPick(ddItem.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
