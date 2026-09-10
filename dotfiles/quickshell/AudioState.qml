pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// AudioState — what the bar wants to know about sound, and the one policy
// WirePlumber will not run for us.
//
//   outputKind / outputGlyph  WHERE output goes: a headset, headphones, an
//                             external box, or the built-in speakers — and
//                             for the speakers, the level (volume waves)
//   micInUse                  an app has the microphone open
//   follow-the-device         put a headset on → output (and, for a headset,
//                             input) moves to it; take it off → back to
//                             where it was
//
// WHY THE POLICY LIVES HERE. WirePlumber remembers the sink the user last
// picked (default.configured.audio.sink) and keeps it for as long as it
// exists — so once anyone chose "Speaker" in Settings, a headset that
// connects later never becomes the output, and a headset that disconnects
// can leave the default pointing at a node that is gone. Every other desktop
// papers over this with its own switch-on-connect; this is ours.
//
// Pure PipeWire; nothing polls. Output kind comes from the default sink's own
// properties — bluez5 nodes carry device.form-factor / api.bluez5.profile,
// ALSA UCM nodes an icon name and a nick ("Headphones") — with the node's
// names as the last resort, which is also what an UNBOUND node (one that just
// appeared) offers. Mic use is a link from the default source to a stream:
// Quickshell 0.3.1 never learns a link's STATE (they stay "Unlinked" even
// when bound — verified 2026-09-10), so the link's existence is the signal;
// a state that IS reported and is not Active is honoured as "not in use".
QtObject {
    id: a

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // properties / audio (volume, mute) are only filled in for BOUND nodes
    property PwObjectTracker _bind: PwObjectTracker {
        objects: [a.sink, a.source].filter(function (n) { return !!n })
    }

    // ── what kind of thing a sink node is ───────────────────────────────────
    // "headset" (has a mic) · "headphones" · "external" (USB DAC, HDMI, a BT
    // speaker) · "internal" (built-in speakers) · "virtual" (ewe_cast, a
    // monitor, a null sink) — works on unbound nodes from names alone
    function kindOf(s) {
        if (!s) return ""
        var p = s.properties || {}
        var api  = String(p["device.api"] || "")
        var icon = String(p["device.icon_name"] || p["device.icon-name"] || "").toLowerCase()
        var ff   = String(p["device.form-factor"] || "").toLowerCase()
        var prof = String(p["api.bluez5.profile"] || "").toLowerCase()
        var name = String(s.name || "").toLowerCase()
        var text = (name + " " + String(s.nickname || "") + " " + String(s.description || "")).toLowerCase()
        if (/^ewe_cast|\.monitor$|^null-|null_sink|^effect_/.test(name)) return "virtual"
        if (api === "bluez5" || name.indexOf("bluez_output") === 0) {
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
    // a device you put on or plug in — the kinds output should FOLLOW
    function isWearable(s) { var k = kindOf(s); return k === "headset" || k === "headphones" }

    readonly property string outputKind: kindOf(a.sink)
    readonly property string outputLabel: a.sink ? String(a.sink.nickname || a.sink.description || a.sink.name || "") : ""
    readonly property real volume: a.sink && a.sink.audio ? a.sink.audio.volume : 0
    readonly property bool muted: a.sink && a.sink.audio ? a.sink.audio.muted : false
    // the bar's glyph: the device when it is worn or external, else the level
    readonly property string outputGlyph: {
        switch (a.outputKind) {
        case "headset":    return Theme.icHeadset
        case "headphones": return Theme.icHeadphones
        case "external":   return Theme.icSpeaker
        }
        if (!a.sink || a.muted || a.volume <= 0.005) return Theme.icVolMute
        return a.volume < 0.34 ? Theme.icVolOff : a.volume < 0.67 ? Theme.icVolLow : Theme.icVolHigh
    }

    // ── microphone in use ───────────────────────────────────────────────────
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
    readonly property string micLabel: a.source ? String(a.source.nickname || a.source.description || a.source.name || "") : ""

    // ── follow the device ───────────────────────────────────────────────────
    property bool followDevices: true
    property bool _primed: false          // the startup batch of nodes is not "new"
    property var _seenSinks: ({})         // node id → name, the sinks already judged
    property var _seenSources: ({})
    property int _defaultSinkId: 0        // the default sink as of the last look
    property int _defaultSourceId: 0
    property string _sinkBefore: ""       // where output was before we moved it to a device
    property string _sourceBefore: ""

    property Timer _primeT: Timer { interval: 2500; running: true; onTriggered: { a._scan(); a._primed = true } }
    property Connections _nodesWatch: Connections { target: Pipewire.nodes; function onValuesChanged() { a._scan() } }
    property Connections _selfWatch: Connections {
        target: a
        function onSinkChanged() { if (a.sink) a._defaultSinkId = a.sink.id }
        function onSourceChanged() { if (a.source) a._defaultSourceId = a.source.id }
    }
    // A2DP ↔ HFP profile flips REPLACE a headset's nodes: the old sink goes,
    // a new one comes a moment later. So a vanished default waits a beat,
    // and a device that appears in that window simply takes over.
    property Timer _restoreSinkT: Timer { interval: 1500; onTriggered: a._restoreSink() }
    property Timer _restoreSourceT: Timer { interval: 1500; onTriggered: a._restoreSource() }

    function _scan() {
        var n = Pipewire.nodes.values
        var sinks = {}, sources = {}, newSinks = [], newSources = []
        for (var i = 0; i < n.length; i++) {
            var d = n[i]
            if (!d || d.isStream || !d.audio) continue
            if (d.isSink) { sinks[d.id] = String(d.name || ""); if (!(d.id in a._seenSinks)) newSinks.push(d) }
            else          { sources[d.id] = String(d.name || ""); if (!(d.id in a._seenSources)) newSources.push(d) }
        }
        var sinkGone = a._defaultSinkId !== 0 && !(a._defaultSinkId in sinks)
        var sourceGone = a._defaultSourceId !== 0 && !(a._defaultSourceId in sources)
        a._seenSinks = sinks
        a._seenSources = sources
        if (!a._primed || !a.followDevices) return

        // put on → follow. Only wearables: a new HDMI or USB box is not a
        // request to hear through it, a headset is.
        for (var j = 0; j < newSinks.length; j++) {
            var s = newSinks[j]
            if (!a.isWearable(s)) continue
            if (a.sink && a.sink.id !== s.id && a._sinkBefore === "" && !a.isWearable(a.sink)) a._sinkBefore = String(a.sink.name || "")
            Log.info("audio", "output follows", s.name)
            Pipewire.preferredDefaultAudioSink = s
            a._restoreSinkT.stop()
            sinkGone = false
            break
        }
        for (var k = 0; k < newSources.length; k++) {
            var r = newSources[k]
            if (String(r.name || "").indexOf("bluez_input") !== 0 && a.kindOf(r) !== "headset") continue
            if (a.source && a.source.id !== r.id && a._sourceBefore === "" && String(a.source.name || "").indexOf("bluez_input") !== 0) a._sourceBefore = String(a.source.name || "")
            Log.info("audio", "input follows", r.name)
            Pipewire.preferredDefaultAudioSource = r
            a._restoreSourceT.stop()
            sourceGone = false
            break
        }
        // taken off → back to where it was
        if (sinkGone) a._restoreSinkT.restart()
        if (sourceGone) a._restoreSourceT.restart()
    }
    function _pick(wantSink, before) {
        var n = Pipewire.nodes.values, want = null, internal = null, any = null
        for (var i = 0; i < n.length; i++) {
            var d = n[i]
            if (!d || d.isStream || !d.audio || d.isSink !== wantSink) continue
            var nm = String(d.name || "")
            if (nm === before) want = d
            if (wantSink) {
                var kd = a.kindOf(d)
                if (kd === "virtual") continue
                if (!internal && kd === "internal") internal = d
            } else {
                if (/\.monitor$|^ewe_cast/.test(nm)) continue
                if (!internal && nm.indexOf("bluez_input") !== 0) internal = d
            }
            if (!any) any = d
        }
        return want || internal || any
    }
    function _restoreSink() {
        var cur = a.sink
        if (cur && (a._defaultSinkId in a._seenSinks) && a.isWearable(cur)) { a._sinkBefore = ""; return }   // a device took over meanwhile
        var pick = a._pick(true, a._sinkBefore)
        if (pick && (!cur || cur.id !== pick.id)) { Log.info("audio", "output back to", pick.name); Pipewire.preferredDefaultAudioSink = pick }
        a._sinkBefore = ""
    }
    function _restoreSource() {
        var cur = a.source
        if (cur && (a._defaultSourceId in a._seenSources) && String(cur.name || "").indexOf("bluez_input") === 0) { a._sourceBefore = ""; return }
        var pick = a._pick(false, a._sourceBefore)
        if (pick && (!cur || cur.id !== pick.id)) { Log.info("audio", "input back to", pick.name); Pipewire.preferredDefaultAudioSource = pick }
        a._sourceBefore = ""
    }

    // what the detector sees — for a log line or `qs ipc` while debugging
    function dump() {
        var g = Pipewire.linkGroups.values, out = []
        for (var i = 0; i < g.length; i++) out.push({ src: g[i].source ? g[i].source.name : null, dst: g[i].target ? g[i].target.name : null, state: g[i].state })
        return JSON.stringify({ sink: a.outputLabel, kind: a.outputKind, volume: a.volume, muted: a.muted, glyph: a.outputGlyph, source: a.micLabel, micInUse: a.micInUse, before: a._sinkBefore, groups: out })
    }
}
