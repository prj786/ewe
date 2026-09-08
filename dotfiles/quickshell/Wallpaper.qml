pragma Singleton
import QtQuick
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

    readonly property bool shouldPause: Globals.lowPower || Globals.locked || Globals.saverActive
    property bool paused: false

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper.sh"

    onShouldPauseChanged: wp._apply()

    function _apply() {
        if (wp.shouldPause === wp.paused) return
        wp.paused = wp.shouldPause
        Log.info("wallpaper", wp.paused ? "freezing video wallpaper" : "resuming video wallpaper",
                 "(battery:" + Globals.lowPower + " locked:" + Globals.locked + " saver:" + Globals.saverActive + ")")
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

    function start() { Log.debug("wallpaper", "policy armed"); wp._readConf() }
}
