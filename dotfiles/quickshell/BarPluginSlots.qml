import QtQuick
import Quickshell

// BarPluginSlots — where third-party bar widgets go (docs/PLUGINS.md).
//
// One per section of the bar strip: left (after the focused app), center
// (the strip's middle, which has had no first-party module since workspace
// switching moved to the dock), right (ahead of the tray). Built-in
// indicators stay hardcoded in Bar.qml; plugins APPEND into a section, in
// the order ewe-plugin lists them (by id). Rearranging is not a 1.0 feature.
//
// Each slot is a Loader over the plugin's bar-widget entry point, gated by
// the same Settings → Top bar map the built-ins use (key `plugin:<id>`,
// absent = shown), so a widget can be hidden without disabling the plugin.
// The entry point's root must be an Item with an implicit size; the Row
// packs it like any other indicator (Theme.barModule / barIcon / spaceS
// are the conventions to follow). A widget that fails to load is
// logged by Qt and takes no space.
Row {
    id: slots
    required property string section
    // the centre section sets this from the left/right rows' extents: on a
    // narrow output the right cluster can reach the middle, and the centre
    // yields rather than draw over it
    property bool fits: true
    spacing: Theme.spaceXs
    // an empty visible Row would still cost the parent Row one `spacing`
    visible: fits && rep.count > 0 && implicitWidth > 0

    Repeater {
        id: rep
        model: PluginHost.barWidgets.filter(function (w) {
            return ((w.barWidget && w.barWidget.defaultSection) || "right") === slots.section
        })
        delegate: Loader {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            active: Globals.barShows("plugin:" + modelData.id)
            visible: active && status === Loader.Ready
            source: "file://" + modelData.entry
            onStatusChanged: {
                if (status === Loader.Error) Log.warn("plugins", modelData.id + "/bar-widget failed to load (see the qml error above)")
                else if (status === Loader.Ready) { Log.debug("plugins", "bar-widget", modelData.id, "in", slots.section); PluginHost._giveSettings(item, modelData.id) }
            }
            // `ewe-plugin set …` → plugins.reload → the widget sees its new values
            Connections { target: PluginHost; function onSettingsChanged() { if (status === Loader.Ready) PluginHost._giveSettings(item, modelData.id) } }
        }
    }
}
