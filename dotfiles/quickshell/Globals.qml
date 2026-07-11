pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Globals — shared, instant shell state (no IPC round-trip for in-shell toggles).
QtObject {
    id: g

    // Project version — the shell's runtime copy. Keep in sync with the repo-root
    // VERSION file (the canonical source used for git tags / releases). Semver, with
    // an -alpha/-beta pre-release suffix until the first stable cut.
    readonly property string version: "0.3.0-alpha"

    property bool quickSettingsOpen: false  // the Quick Settings panel
    property bool dnd: false               // Do Not Disturb (suppresses toasts)
    property var server: null              // set by Notifications.qml (the live NotificationServer)
    property bool vpnActive: false         // any VPN connection up (bar shows a VPN glyph)
    property bool sshTunnelUp: false       // any background ssh -f -N tunnel from Quick Settings is up (bar shows a console glyph)
    property bool caffeine: false          // keep-awake: holds a wayland idle inhibitor (no lock/blank/sleep)
    property bool overviewOpen: false      // GNOME-style window overview (Super tapped alone)
    property bool clipboardOpen: false     // the clipboard-history / emoji popup (scissors icon)
    property bool appMenuOpen: false       // the move-to-workspace dropdown (→ button in the bar's window actions)
    property bool settingsOpen: false      // the Quickshell Settings window (Super+, or the CC gear)
    property real clipAnchorX: 40           // screen-local x of the scissors icon (clipboard opens under it)
    property real appAnchorX: 40            // screen-local x of the move-to button (its dropdown opens under it)

    // ── User-chosen accent colour ─────────────────────────────────────────────
    // Single mutable source the Settings → Theme pane writes; Theme.accent binds to
    // it so the whole shell recolours live. Persisted to ~/.config/quickshell/
    // user-theme.json and re-read here at startup (default = system blue).
    property color accentColor: "#0a84ff"
    property bool tintBorders: false        // mirror window border colour to the accent

    // Animation speed multiplier driving both the QML shell (Theme.dur*) and the
    // Hyprland window animations (Settings writes scaled hl.animation overrides).
    // 1.0 = default; >1 faster; 0 = animations off. Persisted in user-theme.json.
    property real animationSpeed: 1.0

    // ── App appearance (GTK + Qt light/dark) ───────────────────────────────────
    // "dark" | "light". The shell itself is always dark; this drives external
    // GTK/Qt apps via scripts/colorscheme.sh. Persisted in user-theme.json and
    // re-applied at every startup so gsettings stays in sync with the choice.
    property string colorScheme: "dark"
    property Process _csApply: Process {}
    function applyColorScheme() {
        var acc = String(g.accentColor).replace("#", "")
        g._csApply.command = ["sh", "-c", "\"$HOME/.config/quickshell/scripts/colorscheme.sh\" " + g.colorScheme + " " + acc]
        g._csApply.running = false; g._csApply.running = true
    }

    // ── Dock prefs (bottom dock; persisted in user-theme.json) ─────────────────
    property bool dockEnabled: true
    property bool dockAutohide: false       // intelligent hide: slide away, reveal on bottom-edge hover

    // ── Dock popups ────────────────────────────────────────────────────────────
    property bool launcherOpen: false       // pinned-apps / launcher panel
    property bool storeOpen: false           // app-store panel
    property bool placesOpen: false          // places / directories panel (Home, Desktop, … + pinned folders)
    property real launcherAnchorX: 200       // screen-local x of the launcher dock button (popup centers on it)
    property real storeAnchorX: 200          // screen-local x of the store dock button
    property real placesAnchorX: 200         // screen-local x of the places dock button

    // ── System-tray context menu (themed, rendered by TrayMenu.qml) ─────────────
    property bool trayMenuOpen: false
    property var  trayMenuHandle: null       // the clicked item's QsMenuHandle
    property real trayMenuAnchorX: 200       // screen-local x of the tray icon (menu centers on it)

    // ── Pinned apps (desktop ids; persisted in pinned-apps.json) ───────────────
    property var pinnedApps: []
    function isPinned(id) { return (g.pinnedApps || []).indexOf(id) >= 0 }
    function togglePin(id) {
        var a = (g.pinnedApps || []).slice()
        var i = a.indexOf(id)
        if (i >= 0) a.splice(i, 1); else a.push(id)
        g.pinnedApps = a
        g._pinWriter.command = ["sh", "-c", "cat > \"$HOME/.config/quickshell/pinned-apps.json\" <<'QS_EOF'\n" + JSON.stringify(a) + "\nQS_EOF\n"]
        g._pinWriter.running = false; g._pinWriter.running = true
    }
    // ── Pinned places (folder paths; persisted in places.json) ────────────────
    // The Places panel always shows the standard XDG dirs; these are the EXTRA
    // folders the user pinned. Same pattern as pinnedApps.
    property var pinnedPlaces: []
    function isPinnedPlace(p) { return (g.pinnedPlaces || []).indexOf(p) >= 0 }
    function togglePinPlace(p) {
        if (!p) return
        var a = (g.pinnedPlaces || []).slice()
        var i = a.indexOf(p)
        if (i >= 0) a.splice(i, 1); else a.push(p)
        g.pinnedPlaces = a
        g._placesWriter.command = ["sh", "-c", "cat > \"$HOME/.config/quickshell/places.json\" <<'QS_EOF'\n" + JSON.stringify(a) + "\nQS_EOF\n"]
        g._placesWriter.running = false; g._placesWriter.running = true
    }
    property Process _placesWriter: Process {}
    property Process _placesLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/places.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { var j = JSON.parse(this.text); if (Array.isArray(j)) g.pinnedPlaces = j } catch (e) {} } }
    }

    // ── Avatar (~/.face) — shared by Settings (account card) and the lock screen.
    // faceUrl is THE avatar image source everywhere: "" while no ~/.face exists,
    // and cache-busted (?v=) after Settings saves a new one.
    property bool hasFace: false
    property int avatarVersion: 0
    readonly property string faceUrl: hasFace ? "file://" + Quickshell.env("HOME") + "/.face?v=" + avatarVersion : ""
    property Process _faceChk: Process { running: true; command: ["sh", "-c", 'test -f "$HOME/.face"']; onExited: function (code) { g.hasFace = (code === 0) } }
    function recheckFace() { g.avatarVersion++; g._faceChk.running = false; g._faceChk.running = true }

    // ── CPU / memory sampling (shared by the RunCat in the bar + Quick Settings) ─
    property real cpuUsage: 0      // 0..1
    property real memUsage: 0      // 0..1
    property var _prevCpu: null
    property Process _statProc: Process {
        command: ["sh", "-c", "head -1 /proc/stat; echo SEP; grep -E 'MemTotal|MemAvailable' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parts = this.text.split("SEP")
                    var nums = parts[0].trim().split(/\s+/).slice(1).map(Number)
                    var idle = (nums[3] || 0) + (nums[4] || 0)
                    var total = 0; for (var i = 0; i < nums.length; i++) total += (nums[i] || 0)
                    if (g._prevCpu) { var dt = total - g._prevCpu.total, di = idle - g._prevCpu.idle; if (dt > 0) g.cpuUsage = Math.max(0, Math.min(1, (dt - di) / dt)) }
                    g._prevCpu = { total: total, idle: idle }
                    var mt = 0, ma = 0, ml = (parts[1] || "").split("\n")
                    for (var j = 0; j < ml.length; j++) { if (ml[j].indexOf("MemTotal") >= 0) mt = parseInt(ml[j].replace(/\D/g, "")); else if (ml[j].indexOf("MemAvailable") >= 0) ma = parseInt(ml[j].replace(/\D/g, "")) }
                    if (mt > 0) g.memUsage = Math.max(0, Math.min(1, (mt - ma) / mt))
                } catch (e) {}
            }
        }
    }
    property Timer _statTimer: Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: g._statProc.running = true }

    property Process _pinWriter: Process {}
    property Process _pinLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/pinned-apps.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { var j = JSON.parse(this.text); if (Array.isArray(j)) g.pinnedApps = j } catch (e) {} } }
    }

    property Process _themeLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/user-theme.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j && j.accent) g.accentColor = j.accent
                    if (j && j.tintBorders !== undefined) g.tintBorders = j.tintBorders
                    if (j && j.dockEnabled !== undefined) g.dockEnabled = j.dockEnabled
                    if (j && j.dockAutohide !== undefined) g.dockAutohide = j.dockAutohide
                    if (j && j.animationSpeed !== undefined) g.animationSpeed = j.animationSpeed
                    if (j && j.colorScheme) g.colorScheme = j.colorScheme
                } catch (e) {}
                // enforce the persisted (or default-dark) appearance on GTK + Qt
                g.applyColorScheme()
            }
        }
    }
}
