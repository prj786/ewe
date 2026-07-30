pragma Singleton
import QtQuick
import Quickshell

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
    function reapplied() {
        wp.paused = false
        wp._settle.restart()
    }
    // give the new process time to come up before re-asserting the freeze
    property Timer _settle: Timer { interval: 1200; onTriggered: wp._apply() }

    function start() { Log.debug("wallpaper", "policy armed") }
}
