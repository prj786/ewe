import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery — low/critical battery safety. While discharging it warns at 20% and
// 10% (once each), and at ≤5% suspends to protect unsaved work (hypridle locks
// before sleep). Devices without a laptop battery (desktops) are ignored.
// notify-send routes the toast through our own Quickshell notification server.
Scope {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool isBattery: dev && dev.isLaptopBattery
    readonly property bool discharging: dev && dev.state === UPowerDeviceState.Discharging
    readonly property real rawPct: dev ? dev.percentage : 100
    readonly property int pct: Math.round(rawPct)

    // UPower reports percentage on 0–100, and Bar/Quick Settings both scale a
    // 0–1 reading up for display. We must NOT copy that here: 0.8 is genuinely
    // ambiguous (0.8% or 80%?), and guessing wrong in this file suspends the
    // machine. A wrong number on the bar is survivable; a wrong suspend is not —
    // so an ambiguous sample is refused outright. Nothing is lost in practice:
    // on a real drain the 5% latch has already fired long before 1%.
    readonly property bool plausible: rawPct > 1
    property bool _warnedScale: false

    // highest threshold already fired this discharge cycle; re-armed when charging
    property int armed: 101

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "hypr-shell", "-u", urgency,
                                 "-h", "string:x-canonical-private-synchronous:hypr-battery",
                                 title, body])
    }

    function evaluate() {
        if (!isBattery) return
        if (!plausible) {
            if (!_warnedScale) {
                _warnedScale = true
                Log.warn("battery", "UPower reported percentage", rawPct,
                         "— ambiguous scale, holding off low-battery actions")
            }
            return
        }
        if (!discharging) { armed = 101; return }          // charging/full → re-arm
        if (pct <= 5 && armed > 5) {
            armed = 5
            Log.info("battery", "critical at", pct + "% — suspending")
            notify("critical", "Battery critically low", pct + "% — suspending to protect your work.")
            Quickshell.execDetached(["systemctl", "suspend"])
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
}
