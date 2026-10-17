import QtQuick
import Quickshell.Services.UPower
import qs
import ".."

// Glance — the machine, only when it needs you (the owner: "if memory is
// okay I don't care looking at it"): a disk past 85 %, waiting updates, a
// battery under 20 % that is not charging. Nothing to say, no section.
Column {
    id: gl
    spacing: Theme.spaceXs

    readonly property var rows: {
        var out = []
        var g = CompanionState.glance || {}
        var disks = g.disks || []
        for (var i = 0; i < disks.length; i++)
            if (disks[i].used_pct >= 85)
                out.push({ ic: Theme.icWarning, tone: disks[i].used_pct >= 95 ? "danger" : "warning",
                           text: "Disk " + disks[i].path + " is " + disks[i].used_pct + " % full · " + disks[i].free_gb + " GB free",
                           act: "" })
        var up = g.updates ? g.updates.total : 0
        if (up > 0)
            out.push({ ic: Theme.icDownload, tone: "", text: up === 1 ? "1 update is waiting" : up + " updates are waiting",
                       act: "updates" })
        var dev = UPower.displayDevice
        if (Shell.onBattery && dev && dev.isLaptopBattery && dev.percentage < 0.2)
            out.push({ ic: Theme.icBattEmpty, tone: "warning", text: "Battery " + Math.round(dev.percentage * 100) + " %", act: "" })
        return out
    }
    visible: gl.rows.length > 0

    SectionLabel { text: "NEEDS A LOOK" }
    Repeater {
        model: gl.rows
        ListRow {
            required property var modelData
            width: gl.width
            density: "dense"
            glyph: modelData.ic
            glyphColor: modelData.tone === "danger" ? Theme.danger : modelData.tone === "warning" ? Theme.warning : Theme.textSecondary
            label: modelData.text
            kind: modelData.act === "updates" ? "Open Komble" : ""
            onClicked: {
                if (modelData.act === "updates") { Shell.openStore("updates"); CompanionState.dropOpen = false }
            }
        }
    }
}
