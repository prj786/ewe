pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

// Wallpaper — freeze the video wallpaper whenever nobody can benefit from it.
//
// An animated wallpaper decoding continuously is the largest single power draw
// in a setup like this: it runs at the display's refresh rate, forever, whether
// or not anyone is looking. mpvpaper's own --auto-pause covers the case of a
// fullscreen window on top (wallpaper.sh passes it), but it cannot know about
// the three cases the SHELL knows about:
//
//   on battery       an unplugged laptop should not spend watts on decoration
//   locked           the lock surface covers every pixel of it
//   screensaver up   likewise
//
// Freezing is a SIGSTOP, not a kill: the compositor keeps the client's last
// committed frame, so the wallpaper becomes a still image at zero cost and
// resumes mid-frame with no reload. Static wallpapers (swww/swaybg) are already
// free and are left alone.
QtObject {
    id: wp

    // Ultra game mode too (GameMode.qml): a windowed game shares the GPU
    readonly property bool shouldPause: Globals.lowPower || Globals.locked || Globals.saverActive || GameMode.ultra
    property bool paused: false

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper.sh"

    onShouldPauseChanged: wp._apply()

    function _apply() {
        if (wp.shouldPause === wp.paused) return
        wp.paused = wp.shouldPause
        Log.info("wallpaper", wp.paused ? "freezing video wallpaper" : "resuming video wallpaper",
                 "(battery:" + Globals.lowPower + " locked:" + Globals.locked + " saver:" + Globals.saverActive + " game:" + GameMode.ultra + ")")
        Quickshell.execDetached([wp.script, wp.paused ? "--pause" : "--resume"])
    }

    // Re-assert everything (Settings after a change, hotplug, cloud restore).
    function reapply() {
        Quickshell.execDetached([wp.script, "--reapply"])
        wp.reapplied()
    }

    // Call after ANY re-apply, including ones this singleton did not perform.
    // A re-apply spawns a FRESH mpvpaper that is running unpaused, so our idea
    // of the state is stale — without this the wallpaper would keep decoding
    // behind a lock screen until something else happened to toggle.
    signal reapplied()
    onReapplied: { wp.paused = false; wp._settle.restart() }
    // give the new process time to come up before re-asserting the freeze
    property Timer _settle: Timer { interval: 1200; onTriggered: wp._apply() }

    // ── Which file is on which output ─────────────────────────────────────
    // The overview paints the wallpaper itself as its backdrop (an opaque one,
    // so a window is not seen twice — once live, once as its card). The
    // assignments live in generated/wallpapers.conf, written by Settings and
    // read by wallpaper.sh; this is the one reader in the shell, so nothing
    // else has to know the file's shape. `*` is the default, any other key an
    // output name. Re-read after every re-apply, which is when it changes.
    property var _perOutput: ({})
    property string _default: ""
    function pathFor(outputName) {
        var p = wp._perOutput[outputName] || wp._default
        // a video or gif wallpaper cannot be painted by Image; the overview
        // falls back to a flat ground rather than a broken icon
        return /\.(mp4|webm|mkv|mov|avi|m4v|gif)$/i.test(p) ? "" : p
    }
    property Process _conf: Process {
        command: ["sh", "-c", 'cat "$HOME/.config/hypr/generated/wallpapers.conf" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                var per = {}, def = "", ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    var l = ls[i].trim()
                    if (l === "" || l[0] === "#") continue
                    var eq = l.indexOf("="); if (eq < 0) continue
                    var k = l.slice(0, eq), v = l.slice(eq + 1)
                    if (k === "mode" || k === "mute") continue
                    if (k === "*") def = v; else per[k] = v
                }
                wp._perOutput = per; wp._default = def
                Log.debug("wallpaper", "conf read: default=" + def + " outputs=" + JSON.stringify(per))
            }
        }
    }
    function _readConf() { wp._conf.running = false; wp._conf.running = true }

    // ── The decode: the screen's pixels, nothing more ─────────────────────
    // PreserveAspectCrop asks Qt for an image that COVERS sourceSize, so a
    // portrait 4K wallpaper on a 1920x1200 screen was cached as 1920x2400 —
    // twice the pixels anyone paints, held for the whole session by the warm
    // below (18 MB instead of 9 per screen size, measured 2026-11; the
    // owner's 2560-wide display paid 33). sourceClipRect in that scaled
    // space keeps only the centred screen-sized window, which is exactly
    // what PreserveAspectCrop showed. The crop needs the picture's own size:
    // one `identify -ping` per file (ImageMagick is ewe-theme's dependency
    // already). Until it answers — or if it cannot — the rect is null and
    // every reader takes the plain key. The warm, the Overview and the lock
    // all go through clipFor(), so they always agree on ONE cache key.
    property var _dims: ({})            // path → {w, h}; 0x0 = could not read
    property var _dimQueue: []
    function clipFor(outputName, w, h) {
        var p = wp.pathFor(outputName), d = wp._dims[p]
        if (!p || !d || d.w <= 0 || d.h <= 0 || w <= 0 || h <= 0) return Qt.rect(0, 0, 0, 0)
        // the size Qt decodes to for PreserveAspectCrop: the larger ratio,
        // each side rounded (QQuickImageProviderWithOptions::loadSize —
        // checked against Qt 6 in the nest: 1950x1200 asks 1950x2437, not
        // 2438). The centred window of it is pixel-identical to what the
        // unclipped decode painted (compared with ImageMagick, 2026-11).
        var ratio = Math.max(w / d.w, h / d.h)
        var sw = Math.max(w, Math.round(d.w * ratio)), sh = Math.max(h, Math.round(d.h * ratio))
        return Qt.rect(Math.floor((sw - w) / 2), Math.floor((sh - h) / 2), w, h)
    }
    function probeDims(path) {
        if (!path || wp._dims[path] !== undefined || wp._dimQueue.indexOf(path) >= 0) return
        wp._dimQueue = wp._dimQueue.concat([path])
        wp._pumpDims()
    }
    function _pumpDims() {
        if (wp._dimProc.running || wp._dimQueue.length === 0) return
        // through sh so stdout always closes with an answer (no identify,
        // unreadable file: "0 0" = give up on the crop for this file)
        wp._dimProc.command = ["sh", "-c", 'identify -ping -format "%w %h" "$1[0]" 2>/dev/null || echo 0 0', "sh", wp._dimQueue[0]]
        wp._dimProc.running = true
    }
    property Process _dimProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var path = wp._dimQueue[0], m = /^(\d+)\s+(\d+)/.exec(this.text.trim())
                var d = Object.assign({}, wp._dims)
                d[path] = m ? { w: parseInt(m[1], 10), h: parseInt(m[2], 10) } : { w: 0, h: 0 }
                wp._dims = d
                wp._dimQueue = wp._dimQueue.slice(1)
                Log.debug("wallpaper", "size of", path, d[path].w + "x" + d[path].h)
                wp._pumpDims()
            }
        }
    }

    // ── Warm the backdrop decode ──────────────────────────────────────────
    // The Overview and the lock screen paint this file THEMSELVES, at the
    // screen's size. A 3840x2400 JPEG takes a beat to decode, and the window
    // that draws it only exists while it is open — so the wallpaper used to
    // arrive AFTER the window cards. These Images have no visual parent and
    // are never drawn: they hold a reference to the decoded pixmap in Qt's
    // cache from shell start, so the surfaces that DO draw it get a cache hit
    // and are ready on their first frame. The key is (url, sourceSize,
    // sourceClipRect, fillMode) — Qt's pixmap cache keys on the provider options too, and
    // fillMode puts PreserveAspectCrop in them: until 0.41 this Image was
    // Stretch, so it decoded a second copy nobody drew and the Overview
    // still missed the cache. Keep all four byte-identical to Overview.qml.
    property Instantiator _warm: Instantiator {
        model: Quickshell.screens
        delegate: Image {
            required property var modelData
            readonly property string path: wp.pathFor(modelData.name)
            // decode once the crop is known (or known to be unavailable):
            // a key that changes under a loaded Image is a second decode
            source: (path && wp._dims[path] !== undefined) ? "file://" + path : ""
            onPathChanged: wp.probeDims(path)
            Component.onCompleted: wp.probeDims(path)
            sourceSize: Qt.size(modelData.width, modelData.height)
            sourceClipRect: wp.clipFor(modelData.name, modelData.width, modelData.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
            onStatusChanged: if (status === Image.Ready)
                Log.debug("wallpaper", "warmed", path, modelData.width + "x" + modelData.height)
        }
    }

    function start() { Log.debug("wallpaper", "policy armed"); wp._readConf() }
}
