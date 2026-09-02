pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Agenda — THE calendar model the widgets read, whatever feeds it: the
// Nextcloud account (CalDAV, Cloud.qml) first, the optional Google client
// (Google.qml) second, the GOA/EDS bridge (Accounts.qml) last. Also owns the
// reminder notifications, which used to live inside Google.qml and now fire
// for every source alike — once per (event, reminder-time), surviving restarts.
QtObject {
    id: ag

    readonly property string source: Cloud.signedIn && Cloud.events.length > 0 ? "nextcloud"
                                   : Google.signedIn && Google.events.length > 0 ? "google"
                                   : (Accounts.events || []).length > 0 ? "eds" : ""
    // keyed on the events themselves, not on signedIn: right after boot the
    // sign-in probe can lag while cached events are already loaded
    readonly property var events: source === "nextcloud" ? Cloud.events
                                : source === "google" ? Google.events
                                : source === "eds" ? Accounts.events : []
    readonly property string state: source === "nextcloud" ? Cloud.calState : source === "google" ? Google.calState : ""
    readonly property bool connected: Cloud.signedIn || Google.signedIn || (Accounts.events || []).length > 0
    readonly property string hint: connected ? "No upcoming events" : "Sign in to your Nextcloud (Settings → Account) to see events here"

    function refresh() {
        if (Cloud.signedIn) Cloud.fetchCalendar(true)
        if (Google.signedIn) Google.fetchCalendar()
    }

    // ── reminders ─────────────────────────────────────────────────────────────
    readonly property string notifiedPath: Quickshell.env("HOME") + "/.config/quickshell/calendar-notified.json"
    property var _notified: ({})
    property bool _notifiedLoaded: false
    property Process _notifLoad: Process {
        running: true
        // the file moved with the engine; the old Google-era file seeds it once
        command: ["sh", "-c", 'cat "$HOME/.config/quickshell/calendar-notified.json" 2>/dev/null || cat "$HOME/.config/quickshell/google-notified.json" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                try { var j = JSON.parse(this.text); if (j && typeof j === "object") ag._notified = j } catch (e) {}
                ag._notifiedLoaded = true
            }
        }
    }
    property Process _notifWriter: Process {}
    property Timer _remTimer: Timer {
        interval: 60000; repeat: true
        running: ag.events.length > 0 && ag._notifiedLoaded
        onTriggered: ag._checkReminders()
    }
    function _evStartMs(e) {
        if (e.allDay && /^\d{4}-\d{2}-\d{2}$/.test(String(e.start))) {
            var p = String(e.start).split("-")
            return new Date(+p[0], +p[1] - 1, +p[2]).getTime()   // local midnight, not UTC
        }
        var d = new Date(e.start)
        return isNaN(d.getTime()) ? 0 : d.getTime()
    }
    function _checkReminders() {
        var now = Date.now(), dirty = false
        for (var i = 0; i < ag.events.length; i++) {
            var ev = ag.events[i]
            var start = ag._evStartMs(ev)
            if (start === 0 || start < now - 60000) continue     // started already — too late to remind
            for (var r = 0; r < (ev.reminders || []).length; r++) {
                var t = start - ev.reminders[r] * 60000
                var key = ev.id + "@" + t
                if (now < t || now >= t + 120000 || ag._notified[key]) continue
                ag._notified[key] = start
                dirty = true
                var when = new Date(start)
                var lead = ev.reminders[r]
                var body = (lead <= 0 ? "now" : "in " + lead + " min") + " · " + when.toLocaleTimeString(Qt.locale(), "h:mm AP")
                         + (ev.location ? "\n" + ev.location : "")
                         + (ev.video ? "\n" + ev.video : "")
                Quickshell.execDetached(["notify-send", "-a", "Calendar", "-i", "x-office-calendar", ev.summary, body])
            }
        }
        for (var k in ag._notified) if (ag._notified[k] < now - 7 * 86400000) { delete ag._notified[k]; dirty = true }
        if (dirty) HyprMon.atomicWrite(ag._notifWriter, ag.notifiedPath, JSON.stringify(ag._notified))
    }
}
