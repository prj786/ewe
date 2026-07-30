pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Power — battery health, the charge ceiling, and power-profile detail.
//
// UPower already provides percentage and charge state (Battery.qml, the bar and
// Quick Settings all read it), so this deliberately does NOT duplicate that. It
// fills in what UPower's display device does not surface here: design-capacity
// health, cycle count, time remaining, the ASUS charge ceiling, and whether
// power-profiles-daemon has thermally degraded the active profile.
//
// Everything comes from ONE shell probe, on demand — opening Settings → Power,
// waking from suspend, or switching power source. Nothing here polls: none of
// these values move fast enough to justify a timer, and timers are exactly what
// the battery work has spent two commits removing.
QtObject {
    id: pw

    property string batPath: ""
    property int capacity: -1
    property string status: ""
    property int cycleCount: -1
    property real health: -1        // 0..1 — energy_full / energy_full_design
    property real watts: 0          // instantaneous draw or charge rate
    property real hoursLeft: -1     // -1 = unknown, or not discharging

    // ASUS charge ceiling. -1 means the machine has no such attribute at all;
    // present-but-not-writable is the normal state without the udev rule, and is
    // reported honestly rather than failing silently on write.
    property int chargeLimit: -1
    property bool chargeLimitWritable: false
    readonly property bool hasChargeLimit: chargeLimit >= 0

    // power-profiles-daemon (net.hadess.PowerProfiles — tuned-ppd serves the same
    // bus name). PerformanceDegraded is a STRING holding the reason, not a bool:
    // empty means fine, non-empty is e.g. "lap-detected" or a thermal limit.
    property bool ppdRunning: false
    property string degradedReason: ""
    readonly property bool degraded: degradedReason !== ""

    // read-only fallback when no daemon owns the profile
    property string platformProfile: ""
    property var platformChoices: []

    readonly property string chargePath: batPath === "" ? "" : batPath + "/charge_control_end_threshold"

    function refresh() { pw._probe.running = false; pw._probe.running = true }

    property Process _probe: Process {
        command: ["sh", "-c",
            'B=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1); ' +
            'if [ -n "$B" ]; then ' +
            '  echo "bat=$B"; ' +
            '  for f in capacity status energy_now energy_full energy_full_design charge_now charge_full charge_full_design power_now current_now cycle_count charge_control_end_threshold; do ' +
            '    if [ -r "$B/$f" ]; then echo "$f=$(cat "$B/$f" 2>/dev/null)"; fi; ' +
            '  done; ' +
            '  if [ -w "$B/charge_control_end_threshold" ]; then echo "chg_writable=1"; else echo "chg_writable=0"; fi; ' +
            'fi; ' +
            'if [ -r /sys/firmware/acpi/platform_profile ]; then echo "pp=$(cat /sys/firmware/acpi/platform_profile)"; fi; ' +
            'if [ -r /sys/firmware/acpi/platform_profile_choices ]; then echo "ppc=$(cat /sys/firmware/acpi/platform_profile_choices)"; fi; ' +
            'if d=$(busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles PerformanceDegraded 2>/dev/null); then echo "ppd=1"; echo "degraded=$d"; fi; ' +
            'exit 0']
        stdout: StdioCollector { onStreamFinished: pw._parse(this.text) }
    }

    function _parse(text) {
        var lines = String(text).split("\n"), m = {}
        for (var i = 0; i < lines.length; i++) {
            var eq = lines[i].indexOf("=")
            if (eq > 0) m[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
        }
        pw.batPath = m.bat || ""
        pw.capacity = m.capacity !== undefined ? parseInt(m.capacity) : -1
        pw.status = m.status || ""
        pw.cycleCount = m.cycle_count !== undefined ? parseInt(m.cycle_count) : -1

        // energy_* (µWh) on most laptops, charge_* (µAh) on some — accept either
        var now = pw._num(m.energy_now, m.charge_now)
        var full = pw._num(m.energy_full, m.charge_full)
        var design = pw._num(m.energy_full_design, m.charge_full_design)
        var rate = pw._num(m.power_now, m.current_now)
        pw.health = (full > 0 && design > 0) ? (full / design) : -1
        pw.watts = rate > 0 ? rate / 1000000 : 0
        pw.hoursLeft = (rate > 0 && now > 0 && /discharg/i.test(pw.status)) ? (now / rate) : -1

        pw.chargeLimit = m.charge_control_end_threshold !== undefined
            ? parseInt(m.charge_control_end_threshold) : -1
        pw.chargeLimitWritable = m.chg_writable === "1"

        pw.ppdRunning = m.ppd === "1"
        pw.degradedReason = pw._unquote(m.degraded || "")
        pw.platformProfile = m.pp || ""
        pw.platformChoices = String(m.ppc || "").trim().split(/\s+/).filter(function (s) { return s !== "" })

        if (pw.degraded) Log.info("power", "profile degraded:", pw.degradedReason)
    }
    function _num(a, b) {
        var v = parseInt(a !== undefined ? a : b)
        return isNaN(v) ? 0 : v
    }
    // busctl prints a string property as:  s "value"
    function _unquote(s) {
        return String(s).replace(/^s\s+/, "").replace(/^"/, "").replace(/"$/, "")
    }

    property Process _writer: Process {}
    property Timer _reprobe: Timer { interval: 400; onTriggered: pw.refresh() }

    // The kernel exposes the ceiling read-only to non-root. system/udev ships a
    // narrowly-scoped rule that hands this ONE attribute to the wheel group; on
    // a machine without it (or without asusd) the control stays disabled and
    // says why, instead of writing into the void.
    function setChargeLimit(pct) {
        if (!pw.chargeLimitWritable || pw.chargePath === "") {
            Log.warn("power", "charge ceiling not writable — re-run install.sh for the udev rule, or use asusctl")
            return
        }
        var v = Math.max(20, Math.min(100, Math.round(pct)))
        pw._writer.command = ["sh", "-c", 'printf %s "$1" > "$2"', "power", String(v), pw.chargePath]
        pw._writer.running = false; pw._writer.running = true
        pw.chargeLimit = v          // optimistic — the re-probe below is the truth
        pw._reprobe.restart()
        Log.info("power", "charge ceiling →", v + "%")
    }

    function healthText() {
        if (pw.health < 0) return "unknown"
        return Math.round(pw.health * 100) + "% of design"
            + (pw.cycleCount >= 0 ? "  ·  " + pw.cycleCount + " cycles" : "")
    }
    function remainingText() {
        if (pw.hoursLeft < 0) return pw.status !== "" ? pw.status : "—"
        var h = Math.floor(pw.hoursLeft)
        var mins = Math.round((pw.hoursLeft - h) * 60)
        return (h > 0 ? h + " h " : "") + mins + " min left"
            + (pw.watts > 0 ? "  ·  " + pw.watts.toFixed(1) + " W" : "")
    }
}
