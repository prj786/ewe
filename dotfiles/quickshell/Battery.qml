import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery — low/critical battery safety. While discharging it warns at 20% and
// 10% (once each), and at ≤5% hibernates to protect unsaved work (hypridle
// locks before sleep). Hibernate, not suspend: at 5% there is no charge left to
// pay for s2idle's drain — suspend here just postpones dying with work unsaved.
// zzz.sh falls back to suspend where hibernation isn't set up. Devices without
// a laptop battery (desktops) are ignored.
// notify-send routes the toast through our own Quickshell notification server.
Scope {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool isBattery: dev && dev.isLaptopBattery
    readonly property bool discharging: dev && dev.state === UPowerDeviceState.Discharging
    readonly property real rawPct: dev ? dev.percentage : 100
    // Quickshell's UPowerDevice.percentage is a FRACTION, 0.0–1.0 (0.3.1 on
    // the 2026-09-20 machine: a full battery reads 1). The bar and Quick
    // settings scale it the same way. A reading above 1 can only be a
    // 0–100 scale and passes through, so a future Quickshell that changes
    // the contract still lands right; the one ambiguous sample, ≤1 on a
    // 0–100 scale, is a battery at ≤1%, where sleeping is the right call
    // anyway. The old "refuse anything ≤1 as ambiguous" guard refused EVERY
    // reading on this scale: no 20/10 % warnings, no hibernate at 5 %.
    readonly property real pct100: rawPct <= 1 ? rawPct * 100 : rawPct
    readonly property int pct: Math.round(pct100)
    readonly property bool plausible: !isNaN(rawPct) && rawPct >= 0

    // highest threshold already fired this discharge cycle; re-armed when charging
    property int armed: 101

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "ewe", "-u", urgency,
                                 "-h", "string:x-canonical-private-synchronous:hypr-battery",
                                 title, body])
    }

    function evaluate() {
        if (!isBattery) return
        if (!plausible) return                              // no reading at all
        if (!discharging) { armed = 101; return }          // charging/full → re-arm
        if (pct <= 5 && armed > 5) {
            armed = 5
            Log.info("battery", "critical at", pct + "% — hibernating (zzz.sh falls back to suspend)")
            notify("critical", "Battery critically low", pct + "% — sleeping to protect your work.")
            Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/zzz.sh\" hibernate"])
        } else if (pct <= 10 && armed > 10) {
            armed = 10
            notify("critical", "Battery low", pct + "% left — plug in soon.")
        } else if (pct <= 20 && armed > 20) {
            armed = 20
            notify("normal", "Battery at " + pct + "%", "Consider plugging in.")
        }
    }

    onPctChanged: evaluate()
    onDischargingChanged: evaluate()
    Component.onCompleted: evaluate()

    // Suspend still drains, and the charger may have been plugged or unplugged
    // while we were down — so the thresholds have to be re-checked on wake even
    // if UPower's own properties happen not to change afterwards.
    Connections {
        target: Resume
        function onResyncPower() { root.evaluate() }
    }
}
