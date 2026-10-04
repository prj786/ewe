import QtQuick
import qs

// ewe.cast — the Cast page (quickPage.key "cast", the key the shell had):
// the whole flow lives here (RFC-004): the sink list from ewe-castd
// (Miracast + Chromecast), pick a TV → the shell's SharePicker → streaming.
// No foreign window. Reached from the rail, the tile, Super+Shift+C and
// `qs ipc call quicksettings tab cast`.
Column {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    spacing: Theme.spaceS

    // every time the page comes on screen, ask the daemon for the displays in
    // range (what the shell's setTab("cast") did)
    onPanelOpenChanged: if (root.panelOpen) CastState.send("scan")

    // the switch is on while a session runs; turning it off hangs up
    QsPageHead {
        title: "Cast"
        busy: CastState.casting && !CastState.streaming
        note: CastState.streaming ? "Casting to " + CastState.sinkName
            : CastState.casting ? "Connecting…" : ""
        hasSwitch: CastState.casting
        on: CastState.casting
        onToggled: CastState.send("stop")
    }
    // while a session is being built, narrate the daemon's state where the
    // person is looking — the same line the toasts carry
    QsNote { visible: CastState.casting && !CastState.streaming && CastState.detail !== ""; text: CastState.detail }
    // nothing yet — an honest empty state instead of a broken-looking box
    Row {
        visible: root.panelOpen && !CastState.casting && CastState.sinks.length === 0
        spacing: Theme.spaceS
        leftPadding: Theme.spaceS
        readonly property bool noEngine: CastState.detail.indexOf("not installed") !== -1
        Spinner { visible: !parent.noEngine; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
        TextCaption {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.noEngine ? CastState.detail : "Looking for displays…"
        }
    }
    ListWell {
        flush: true
        visible: root.panelOpen && !CastState.casting && CastState.sinks.length > 0
        Repeater {
            model: root.panelOpen ? CastState.sinks : []
            delegate: ListRow {
                required property var modelData
                glyph: Theme.icCast
                label: modelData.name
                kind: modelData.kind === "chromecast" ? "Chromecast" : modelData.kind === "miracast" ? "Miracast" : ""
                onClicked: CastState.send("start", modelData.id)
            }
        }
    }
}
