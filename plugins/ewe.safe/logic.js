.pragma library

// ewe.safe — the plugin's plain logic, with no QML in it, so tests/ can run
// it in a bare engine (tests/tst_logic.qml). Everything here works on the
// JSON `ewe-safe` prints (ewe-safe docs/PROTOCOL.md v1): status replies,
// `watch` lines, item summaries. Nothing here ever sees a password — the
// shell never asks for one; copies go through the daemon.

// reopened within this long, Quick Access keeps the search where it was
// (copy the username, paste, come back for the password)
var REMEMBER_QUERY_MS = 120000

// ── state ──────────────────────────────────────────────────────────────────
//   phase  missing   ewe-safe isn't installed (no binary)
//          down      the CLI answered but the daemon can't be reached
//          new       no safe on this machine yet
//          locked    set up, locked
//          unlocked  set up, open
function blank() {
    return { phase: "missing", items: -1, readOnly: false, reasons: [],
             place: null, sync: null, keyChanged: false, message: "", lockReason: "" }
}

function copyOf(s) {
    var o = {}
    for (var k in s) o[k] = s[k]
    return o
}

// a `status` reply (or `watch`'s first line) → state
function fromStatus(s, d) {
    var o = copyOf(s)
    if (!d || typeof d !== "object") return o
    if (d.ok === false) {
        if (d.error === "daemon-unavailable") { o.phase = "down"; o.message = d.message || "" }
        else if (d.error === "not-set-up") o.phase = "new"
        else if (d.error === "key-changed") o.keyChanged = true
        return o
    }
    if (!("set_up" in d)) return o
    o.phase = !d.set_up ? "new" : (d.locked ? "locked" : "unlocked")
    o.items = typeof d.items === "number" ? d.items : -1
    o.readOnly = !!d.read_only
    o.reasons = d.reasons || []
    o.place = d.place || null
    o.sync = d.sync || null
    o.message = ""
    if (!d.locked) o.keyChanged = false
    return o
}

// one `ewe-safe watch` line → { state, refresh } — refresh = ask `status`
// again (the counts a bare event doesn't carry)
function applyLine(s, line) {
    var d = null
    try { d = JSON.parse(line) } catch (e) { return { state: s, refresh: false } }
    if (!d || typeof d !== "object") return { state: s, refresh: false }
    if (!("event" in d)) return { state: fromStatus(s, d), refresh: false }
    var o = copyOf(s)
    switch (d.event) {
    case "status":
        return { state: fromStatus(s, d.status || d), refresh: false }
    case "unlocked":
        o.phase = "unlocked"; o.keyChanged = false; o.lockReason = ""
        return { state: o, refresh: true }
    case "locked":
        if (o.phase === "unlocked") o.phase = "locked"
        o.items = -1; o.lockReason = d.reason || ""
        return { state: o, refresh: false }
    case "changed":
        return { state: o, refresh: true }
    case "sync":
        if (d.sync) o.sync = d.sync
        return { state: o, refresh: false }
    case "daemon-gone":
        o.phase = "down"; o.message = ""
        return { state: o, refresh: false }
    }
    return { state: o, refresh: false }
}

// the dot on the bar glyph: something the user should look at
function attention(s) {
    if (s.keyChanged) return "danger"
    if (s.phase === "down") return "warning"
    var y = s.sync
    if (!y) return ""
    if (y.state === "error") return "danger"
    if (y.warning === "rollback") return "danger"
    if (y.warning) return "warning"
    return ""
}

// "2 min ago" · "just now" · "3 h ago" · "12 Sep" (writing guide: largest
// sensible unit). `now` in ms so tests can pin it.
function ago(iso, now) {
    if (!iso) return ""
    var t = Date.parse(iso)
    if (isNaN(t)) return ""
    var s = Math.max(0, Math.round((now - t) / 1000))
    if (s < 45) return "just now"
    var m = Math.round(s / 60)
    if (m < 60) return m + " min ago"
    var h = Math.round(m / 60)
    if (h < 24) return h + " h ago"
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var d = new Date(t)
    return d.getUTCDate() + " " + months[d.getUTCMonth()]
}

// the line at the foot of Quick Access and under the tile — never a sync
// button (house rule 6): Safe syncs by itself, this only says how it went
function syncLine(s, now) {
    if (s.keyChanged) return "The master password was changed on another computer."
    // down: Quick Access's own line and the bar's dot already say it
    if (s.phase === "down") return ""
    var y = s.sync
    if (!y) return ""
    if (y.warning === "rollback") return "Your server gave an older copy. Safe kept yours."
    if (y.state === "error") return y.message || "Safe can't reach your safe's place."
    if (y.state === "offline") return "Offline — changes are saved on this computer."
    if (y.pending || y.state === "pending") return "Not uploaded yet."
    if (y.state === "local") return "On this computer only."
    var when = ago(y.last, now)
    var line = when ? "In sync · " + when : "In sync"
    if (y.warning === "single-writer") line += " · one computer at a time"
    return line
}

// the tile's status line — one short line, like Wi-Fi's "On" (the count
// lives in Quick Access; "Unlocked · 8 items" wrapped the half-row tile)
function tileSub(s) {
    switch (s.phase) {
    case "missing": return "Not installed"
    case "down": return "Not running"
    case "new": return "Not set up"
    case "locked": return s.keyChanged ? "Locked · new password" : "Locked"
    }
    return s.readOnly ? "Read-only" : "Unlocked"
}

// ── items ──────────────────────────────────────────────────────────────────
// "https://www.discord.com/login" → "discord.com"
function host(url) {
    if (!url) return ""
    var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(url)
    var h = (m ? m[1] : url.split(/[\/?#]/)[0]).toLowerCase()
    return h.indexOf("www.") === 0 ? h.slice(4) : h
}

// what a row says on its right: the site, else the folder
function rowCaption(it) {
    var h = it.urls && it.urls.length ? host(it.urls[0]) : ""
    return h || it.folder || ""
}

// the kinds Quick Access knows how to use; Safe's other kinds (SSH keys,
// cards, addresses — PROTOCOL.md: "a caller that knows only logins and
// notes skips other kinds") live in the Safe window
var KINDS = { login: true, note: true }

// rank items for what was typed: title start > word start in the title >
// anywhere in the title > username / site / tag / folder. Empty query →
// everything, logins before notes, by title (the CLI's own order kept).
function rank(items, query) {
    var q = (query || "").trim().toLowerCase()
    var out = []
    for (var i = 0; i < items.length; i++) {
        var it = items[i], t = (it.title || "").toLowerCase()
        if (!KINDS[it.kind || "login"]) continue
        var score = 0
        if (!q) score = it.kind === "note" ? 1 : 2
        else if (t.indexOf(q) === 0) score = 100
        else if ((" " + t).indexOf(" " + q) >= 0) score = 80
        else if (t.indexOf(q) >= 0) score = 60
        else {
            var rest = [it.username || ""]
            var urls = it.urls || []
            for (var u = 0; u < urls.length; u++) rest.push(host(urls[u]))
            var tags = (it.tags || []).concat(it.apps || [])
            for (var g = 0; g < tags.length; g++) rest.push(tags[g])
            rest.push(it.folder || "")
            if (rest.join(" ").toLowerCase().indexOf(q) >= 0) score = 40
        }
        if (score > 0) out.push({ item: it, score: score, i: i })
    }
    out.sort(function (a, b) { return b.score - a.score || a.i - b.i })
    var r = []
    for (var k = 0; k < out.length; k++) r.push(out[k].item)
    return r
}

// "481093" → "481 093"; 8 digits → "4810 9312"
function otpText(v) {
    v = String(v || "")
    if (v.length === 6) return v.slice(0, 3) + " " + v.slice(3)
    if (v.length === 8) return v.slice(0, 4) + " " + v.slice(4)
    return v
}

// ── argv — every call is argv, never a shell ──────────────────────────────
function copyArgv(tool, id, field) { return [tool, "copy", id, "--field", field] }
function otpArgv(tool, id) { return [tool, "reveal", id, "--field", "otp", "--json"] }
// the Safe window: "" = just open it; "show" an item; "new"; "unlock"
function appArgv(app, what, id) {
    if (what === "show") return [app, "--show", id]
    if (what === "new") return [app, "--new"]
    if (what === "import") return [app, "--import"]
    if (what === "unlock") return [app, "--unlock"]
    return [app]
}

// the toast after a copy — what was copied, and when it goes away
function copiedText(field, clearAfter) {
    var what = field === "password" ? "the password"
             : field === "username" ? "the username"
             : field === "otp" ? "the one-time code" : field
    var s = "Copied " + what + "."
    if (clearAfter > 0) s += " It clears in " + clearAfter + " s."
    return s
}
