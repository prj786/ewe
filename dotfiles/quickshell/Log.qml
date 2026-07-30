pragma Singleton
import QtQuick
import Quickshell

// Log — the shell's one logging choke point.
//
// Before this existed the whole shell had a single console.log in ~12k lines of
// QML: every failure lived only in a UI-string property, invisible unless the one
// panel that renders it happened to be open, and several of those properties had
// no reader at all. Anything worth knowing about now goes through here, so there
// is exactly one place to turn the detail up when a session misbehaves — and one
// place for the startup diagnostic to write into.
//
// Level comes from the environment so a verbose session needs no edit and no
// rebuild (set it in start-hyprland.sh, or `HS_LOG=debug qs` when iterating):
//
//   HS_LOG=error|warn|info|debug     global level (default: warn — quiet)
//   HS_LOG_MODULES=google,kdeconnect force just these modules to debug
//
// Call it as Log.warn("google", "token refresh failed:", reason). The module tag
// is a plain lowercase string (one per service — "google", "kdeconnect",
// "display", "battery"), and a line comes out as:
//
//   hypr-shell W google: token refresh failed: network: timed out
//
// Levels are a guide, not a ceremony: error = the user lost a capability, warn =
// something failed but we recovered or degraded, info = a state change worth
// seeing in a bug report, debug = per-operation detail.
QtObject {
    id: log

    // ordered levels — the ints are the comparison, the names are the env API
    readonly property int levelError: 0
    readonly property int levelWarn: 1
    readonly property int levelInfo: 2
    readonly property int levelDebug: 3

    readonly property int level: log._parseLevel(Quickshell.env("HS_LOG") || "", log.levelWarn)

    // modules pinned to debug regardless of the global level, so one chatty
    // service can be investigated without drowning in every other one
    readonly property var verboseModules: {
        var out = {}
        var parts = (Quickshell.env("HS_LOG_MODULES") || "").split(",")
        for (var i = 0; i < parts.length; i++) {
            var m = parts[i].trim().toLowerCase()
            if (m !== "") out[m] = true
        }
        return out
    }

    function _parseLevel(name, fallback) {
        var n = String(name).trim().toLowerCase()
        if (n === "error") return log.levelError
        if (n === "warn" || n === "warning") return log.levelWarn
        if (n === "info") return log.levelInfo
        if (n === "debug" || n === "trace") return log.levelDebug
        return fallback
    }

    // cheap gate for hot paths — check this before building an expensive message,
    // since the arguments to warn()/debug() are evaluated whether we print or not
    function wants(module, lvl) {
        return lvl <= log.level || !!log.verboseModules[String(module).toLowerCase()]
    }

    function _emit(lvl, tag, module, args) {
        if (!log.wants(module, lvl)) return
        var parts = []
        for (var i = 1; i < args.length; i++) parts.push(args[i])
        var line = "hypr-shell " + tag + " " + module + ": " + parts.join(" ")
        // route through the matching console call so Qt's own category filtering
        // and journal severity still work
        if (lvl === log.levelError) console.error(line)
        else if (lvl === log.levelWarn) console.warn(line)
        else console.log(line)
    }

    function error(module) { log._emit(log.levelError, "E", module, arguments) }
    function warn(module)  { log._emit(log.levelWarn,  "W", module, arguments) }
    function info(module)  { log._emit(log.levelInfo,  "I", module, arguments) }
    function debug(module) { log._emit(log.levelDebug, "D", module, arguments) }
}
