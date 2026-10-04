pragma Singleton
import QtQuick
import qs

// Insomnia — the one state the service, the tile and the pill glyph share.
// A plugin's entry points are loaded as separate files; this singleton
// (registered by the qmldir beside it) is how they see the same `on`.
//
//   on        the idle inhibitor is held (Service.qml) — no auto-lock, no
//             screen blank, no auto-suspend
//   autoOff   minutes after which `on` drops by itself; 0 = never. Comes
//             from the plugin's `autoOff` setting (Service.qml hands it over)
//   until     ms epoch when that happens, 0 while nothing is scheduled
QtObject {
    id: ins

    property bool on: false
    property int autoOff: 0
    property double since: 0                 // ms epoch of the last turn-on
    readonly property double until: ins.on && ins.autoOff > 0 ? ins.since + ins.autoOff * 60000 : 0
    property double now: Date.now()
    readonly property int minutesLeft: ins.until > 0 ? Math.max(0, Math.ceil((ins.until - ins.now) / 60000)) : 0
    // "45 min" · "1 h 20 min" · "2 h" (writing guide: largest sensible unit)
    readonly property string leftText: ins.fmt(ins.minutesLeft)

    function fmt(min) {
        if (min < 60) return min + " min"
        var h = Math.floor(min / 60), m = min % 60
        return m === 0 ? h + " h" : h + " h " + m + " min"
    }
    function set(v) {
        v = !!v
        if (v && !ins.on) ins.since = Date.now()
        ins.now = Date.now()
        ins.on = v
    }
    function toggle() { ins.set(!ins.on) }
    function status() {
        return JSON.stringify({ on: ins.on, autoOff: ins.autoOff, minutesLeft: ins.minutesLeft, until: ins.until })
    }

    // the auto-off: one shot at `until`; re-armed whenever it moves (a new
    // turn-on, a changed setting)
    onUntilChanged: ins._arm()
    function _arm() {
        ins._off.stop()
        if (ins.until <= 0) return
        ins.now = Date.now()
        ins._off.interval = Math.max(1, ins.until - ins.now)
        ins._off.start()
    }
    property Timer _off: Timer {
        repeat: false
        onTriggered: {
            if (!ins.on) return
            var after = ins.autoOff
            ins.set(false)
            Shell.toast("Insomnia turned off after " + ins.fmt(after))
            Log.info("ewe.insomnia", "auto-off after", after, "min")
        }
    }
    // keeps `minutesLeft` honest for the tile's status while a countdown runs
    property Timer _tick: Timer {
        interval: 30000
        repeat: true
        running: ins.until > 0
        onTriggered: ins.now = Date.now()
    }
}
