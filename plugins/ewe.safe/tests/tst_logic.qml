import QtQuick
import QtTest
import "../logic.js" as Logic

// logic.js in a real QML engine (qmltestrunner, offscreen) — the JSON
// ewe-safe prints (docs/PROTOCOL.md v1) turned into what the plugin shows.
TestCase {
    name: "SafeLogic"

    function status(o) {
        var d = { ok: true, set_up: true, locked: false, read_only: false, place: { kind: "nextcloud" },
                  items: 11, sync: { state: "in-sync", last: "2026-10-14T16:00:00Z", pending: false, warning: null } }
        for (var k in o) d[k] = o[k]
        return d
    }
    function lines(s, ls) {
        var r = { state: s, refresh: false }
        for (var i = 0; i < ls.length; i++) r = Logic.applyLine(r.state, ls[i])
        return r
    }

    function test_phases() {
        var b = Logic.blank()
        compare(b.phase, "missing")
        compare(Logic.fromStatus(b, status({})).phase, "unlocked")
        compare(Logic.fromStatus(b, status({ locked: true, items: null })).phase, "locked")
        compare(Logic.fromStatus(b, status({ set_up: false })).phase, "new")
        compare(Logic.fromStatus(b, { ok: false, error: "daemon-unavailable", message: "no socket" }).phase, "down")
        compare(Logic.fromStatus(b, { ok: false, error: "not-set-up" }).phase, "new")
        compare(Logic.fromStatus(b, status({})).items, 11)
        compare(Logic.fromStatus(b, status({ locked: true, items: null })).items, -1)
    }

    // a new machine whose ewe.conf names the account's safe: still "new",
    // but offered — the tile says where it is, a set-up machine never is
    function test_offer() {
        var b = Logic.blank()
        compare(b.offer, null)
        var o = Logic.fromStatus(b, status({ set_up: false, offer: { place: "nextcloud", location: "ewe/safe/passwords.kdbx" } }))
        compare(o.phase, "new")
        compare(o.offer.place, "nextcloud")
        compare(Logic.tileSub(o), "In your account")
        compare(Logic.tileSub(Logic.fromStatus(b, status({ set_up: false }))), "Not set up")
        compare(Logic.fromStatus(o, status({})).offer, null)
    }

    function test_watch_first_line_either_shape() {
        var plain = Logic.applyLine(Logic.blank(), JSON.stringify(status({ locked: true })))
        compare(plain.state.phase, "locked")
        var wrapped = Logic.applyLine(Logic.blank(), JSON.stringify({ v: 1, event: "status", status: status({}) }))
        compare(wrapped.state.phase, "unlocked")
    }

    function test_events() {
        var s = Logic.fromStatus(Logic.blank(), status({ locked: true, items: null }))
        var r = Logic.applyLine(s, '{"v":1,"event":"unlocked"}')
        compare(r.state.phase, "unlocked")
        verify(r.refresh)
        r = Logic.applyLine(r.state, '{"v":1,"event":"locked","reason":"screen"}')
        compare(r.state.phase, "locked")
        compare(r.state.lockReason, "screen")
        compare(r.state.items, -1)
        r = Logic.applyLine(r.state, '{"v":1,"event":"changed"}')
        verify(r.refresh)
        r = Logic.applyLine(r.state, '{"v":1,"event":"sync","sync":{"state":"offline","pending":true}}')
        compare(r.state.sync.state, "offline")
        r = Logic.applyLine(r.state, '{"event":"daemon-gone"}')
        compare(r.state.phase, "down")
        // garbage leaves the state alone
        var before = r.state
        compare(Logic.applyLine(before, "not json").state, before)
    }

    function test_locked_event_keeps_new_and_down() {
        var s = Logic.fromStatus(Logic.blank(), status({ set_up: false }))
        compare(Logic.applyLine(s, '{"v":1,"event":"locked","reason":"idle"}').state.phase, "new")
    }

    function test_attention() {
        var s = Logic.fromStatus(Logic.blank(), status({}))
        compare(Logic.attention(s), "")
        s.sync = { state: "error", message: "not signed in" }
        compare(Logic.attention(s), "danger")
        s.sync = { state: "in-sync", warning: "rollback" }
        compare(Logic.attention(s), "danger")
        s.sync = { state: "in-sync", warning: "single-writer" }
        compare(Logic.attention(s), "warning")
        s.sync = { state: "pending", pending: true }
        compare(Logic.attention(s), "")
        var k = Logic.fromStatus(Logic.fromStatus(Logic.blank(), status({ locked: true })), { ok: false, error: "key-changed" })
        compare(Logic.attention(k), "danger")
        compare(Logic.attention(Logic.fromStatus(Logic.blank(), { ok: false, error: "daemon-unavailable" })), "warning")
    }

    function test_unlock_clears_key_changed() {
        var k = Logic.fromStatus(Logic.fromStatus(Logic.blank(), status({ locked: true })), { ok: false, error: "key-changed" })
        verify(k.keyChanged)
        verify(!Logic.applyLine(k, '{"v":1,"event":"unlocked"}').state.keyChanged)
    }

    function test_sync_line() {
        var now = Date.parse("2026-10-14T16:02:00Z")
        var s = Logic.fromStatus(Logic.blank(), status({}))
        compare(Logic.syncLine(s, now), "In sync · 2 min ago")
        s.sync = { state: "in-sync", last: "2026-10-14T16:01:50Z" }
        compare(Logic.syncLine(s, now), "In sync · just now")
        s.sync = { state: "pending", pending: true }
        compare(Logic.syncLine(s, now), "Not uploaded yet.")
        s.sync = { state: "offline" }
        compare(Logic.syncLine(s, now), "Offline — changes are saved on this computer.")
        s.sync = { state: "error", message: "not signed in to your ewe account" }
        compare(Logic.syncLine(s, now), "not signed in to your ewe account")
        s.sync = { state: "local" }
        compare(Logic.syncLine(s, now), "On this computer only.")
        s.sync = { state: "in-sync", last: "2026-10-14T16:00:00Z", warning: "single-writer" }
        compare(Logic.syncLine(s, now), "In sync · 2 min ago · one computer at a time")
        s.sync = { state: "in-sync", warning: "rollback" }
        compare(Logic.syncLine(s, now), "Your server gave an older copy. Safe kept yours.")
        compare(Logic.syncLine(Logic.fromStatus(Logic.blank(), { ok: false, error: "daemon-unavailable", message: "x" }), now), "")
        compare(Logic.ago("2026-09-12T08:00:00Z", now), "12 Sep")
        compare(Logic.ago("2026-10-14T13:00:00Z", now), "3 h ago")
        compare(Logic.ago("", now), "")
    }

    function test_tile_sub() {
        compare(Logic.tileSub(Logic.blank()), "Not installed")
        compare(Logic.tileSub(Logic.fromStatus(Logic.blank(), status({}))), "Unlocked")
        compare(Logic.tileSub(Logic.fromStatus(Logic.blank(), status({ locked: true }))), "Locked")
        compare(Logic.tileSub(Logic.fromStatus(Logic.blank(), status({ read_only: true }))), "Read-only")
        compare(Logic.tileSub(Logic.fromStatus(Logic.blank(), { ok: false, error: "daemon-unavailable" })), "Not running")
    }

    function test_host_and_caption() {
        compare(Logic.host("https://www.Discord.com/login?x=1"), "discord.com")
        compare(Logic.host("http://192.168.1.1:8080/"), "192.168.1.1")
        compare(Logic.host("example.org/path"), "example.org")
        compare(Logic.rowCaption({ urls: ["https://github.com/login"], folder: "Work" }), "github.com")
        compare(Logic.rowCaption({ urls: [], folder: "Work" }), "Work")
    }

    function test_rank() {
        var items = [
            { id: "1", kind: "login", title: "Example Bank", username: "sam", urls: ["https://bank.example"], tags: ["money"] },
            { id: "2", kind: "note", title: "Home Wi-Fi", username: "", urls: [], tags: ["home"] },
            { id: "3", kind: "login", title: "GitHub", username: "sam-shepherd", urls: ["https://github.com"], tags: ["work"] },
            { id: "4", kind: "login", title: "Work VPN", username: "sam", urls: [], tags: [], folder: "Work" }
        ]
        // empty query: logins first, the CLI's order otherwise
        compare(Logic.rank(items, "").map(function (i) { return i.id }).join(), "1,3,4,2")
        compare(Logic.rank(items, "git")[0].id, "3")                  // title start
        compare(Logic.rank(items, "bank")[0].id, "1")                 // word start
        compare(Logic.rank(items, "money").map(function (i) { return i.id }).join(), "1")   // a tag
        compare(Logic.rank(items, "shepherd").map(function (i) { return i.id }).join(), "3") // a username
        compare(Logic.rank(items, "work").map(function (i) { return i.id }).join(), "4,3")  // title before tag
        compare(Logic.rank(items, "zzz").length, 0)
        // kinds Quick Access can't use stay in the Safe window
        var more = items.concat([
            { id: "5", kind: "card", title: "Work Visa", username: "", urls: [], tags: [] },
            { id: "6", kind: "address", title: "Work address", username: "", urls: [], tags: [] },
            { id: "7", kind: "ssh-key", title: "Work laptop key", username: "", urls: [], tags: [] }
        ])
        compare(Logic.rank(more, "").map(function (i) { return i.id }).join(), "1,3,4,2")
        compare(Logic.rank(more, "work").map(function (i) { return i.id }).join(), "4,3")
    }

    function test_otp_text() {
        compare(Logic.otpText("481093"), "481 093")
        compare(Logic.otpText("48109312"), "4810 9312")
        compare(Logic.otpText(""), "")
    }

    function test_argv_never_a_shell() {
        compare(Logic.copyArgv("ewe-safe", "id-1", "password"), ["ewe-safe", "copy", "id-1", "--field", "password"])
        compare(Logic.otpArgv("ewe-safe", "id-1"), ["ewe-safe", "reveal", "id-1", "--field", "otp", "--json"])
        compare(Logic.appArgv("ewe-safe-app", "show", "id-1"), ["ewe-safe-app", "--show", "id-1"])
        compare(Logic.appArgv("ewe-safe-app", "new"), ["ewe-safe-app", "--new"])
        compare(Logic.appArgv("ewe-safe-app", ""), ["ewe-safe-app"])
        // an id with shell characters stays one argument
        compare(Logic.copyArgv("ewe-safe", "$(rm -rf ~)", "otp")[2], "$(rm -rf ~)")
    }

    function test_copied_text() {
        compare(Logic.copiedText("password", 30), "Copied the password. It clears in 30 s.")
        compare(Logic.copiedText("otp", 0), "Copied the one-time code.")
    }
}
