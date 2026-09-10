pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// AudioState — the two things the bar wants to know about sound that the
// volume slider does not tell: WHERE output goes (a headset, headphones, an
// external box — or just the built-in speakers) and whether anything is
// LISTENING to the microphone right now. Pure PipeWire; nothing polls.
//
// Output kind comes from the default sink's own properties — bluez5 nodes
// carry device.form-factor / api.bluez5.profile, ALSA UCM nodes carry an
// icon name and a nick ("Headphones") — with the node's names as the last
// resort. Mic use is the default source's link state: a link is Active only
// while the app on the other end is really capturing (a corked Discord shows
// Paused), which is the honest "someone is recording" signal.
QtObject {
    id: a

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // properties are only filled in for BOUND nodes
    property PwObjectTracker _bind: PwObjectTracker {
        objects: [a.sink, a.source].filter(function (n) { return !!n })
    }

    // "headset" (has a mic) · "headphones" · "external" (USB DAC, HDMI, a BT
    // speaker) · "internal" (built-in speakers) · "" (no sink)
    readonly property string outputKind: {
        var s = a.sink
        if (!s) return ""
        var p = s.properties || {}
        var api  = String(p["device.api"] || "")
        var icon = String(p["device.icon_name"] || p["device.icon-name"] || "").toLowerCase()
        var ff   = String(p["device.form-factor"] || "").toLowerCase()
        var prof = String(p["api.bluez5.profile"] || "").toLowerCase()
        var text = (String(s.name || "") + " " + String(s.nickname || "") + " " + String(s.description || "")).toLowerCase()
        if (api === "bluez5" || text.indexOf("bluez_output") >= 0) {
            if (ff === "headset" || /headset|hfp|hsp/.test(prof) || /headset/.test(icon + " " + text)) return "headset"
            if (ff === "headphone" || ff === "headphones" || /headphone/.test(icon + " " + text)) return "headphones"
            if (ff === "speaker" || ff === "portable" || ff === "car" || /speaker/.test(text)) return "external"
            return "headphones"   // an unnamed Bluetooth audio device is worn far more often than not
        }
        if (/headset/.test(icon + " " + text)) return "headset"
        if (/headphone/.test(icon + " " + text)) return "headphones"
        if (/hdmi|displayport|\.usb-|usb_|usb-/.test(text) || ff === "external" || /external/.test(icon)) return "external"
        return "internal"
    }
    readonly property string outputLabel: a.sink ? String(a.sink.nickname || a.sink.description || a.sink.name || "") : ""
    // the glyph for a kind — "" for built-in speakers: the bar names the
    // unusual, not the default
    function glyph(kind) {
        switch (kind) {
        case "headset":    return Theme.icHeadset
        case "headphones": return Theme.icHeadphones
        case "external":   return Theme.icSpeaker
        }
        return ""
    }
    readonly property string outputGlyph: glyph(outputKind)

    // A link from the default source to a stream = an app has the mic open.
    // Quickshell 0.3.1 never learns a link's STATE (they stay "Unlinked" even
    // when bound — verified 2026-09-10), so the link's existence is the
    // signal; a state that is actually reported and is not Active (a corked
    // stream, should a later Quickshell deliver it) is honoured as "not in
    // use". Global link groups, so a group appearing or vanishing
    // re-evaluates this.
    readonly property bool micInUse: {
        var src = a.source
        if (!src) return false
        var g = Pipewire.linkGroups.values
        for (var i = 0; i < g.length; i++) {
            var lg = g[i]
            if (!lg) continue
            if (lg.state >= PwLinkState.Init && lg.state !== PwLinkState.Active) continue
            var other = (lg.source && lg.source.id === src.id) ? lg.target
                      : (lg.target && lg.target.id === src.id) ? lg.source : null
            if (other && other.isStream) return true
        }
        return false
    }
    // what the detector sees — for a log line or `qs ipc` while debugging
    function dump() {
        var g = Pipewire.linkGroups.values, out = []
        for (var i = 0; i < g.length; i++) out.push({ src: g[i].source ? g[i].source.name : null, dst: g[i].target ? g[i].target.name : null, state: g[i].state })
        return JSON.stringify({ sink: a.outputLabel, kind: a.outputKind, source: a.micLabel, micInUse: a.micInUse, groups: out })
    }
    readonly property string micLabel: a.source ? String(a.source.nickname || a.source.description || a.source.name || "") : ""
}
