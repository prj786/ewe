import QtQuick

// SectionTitle — a pane's section heading (spec: fs-small, 600, fg3; 24 px
// above, 8 px below, zero top margin on the first one so every pane's first
// heading lands on the same baseline). The paddings subtract the parent
// Column's own spacing so the visual gaps come out at the spec's figures.
//     SectionTitle { text: "Output" }
Text {
    id: st
    property bool first: st.parent ? (st.parent.children.length > 0 && st.parent.children[0] === st) : true
    readonly property int _gap: st.parent && st.parent.spacing !== undefined ? st.parent.spacing : 0
    topPadding: st.first ? 0 : Math.max(0, 24 - _gap)
    bottomPadding: Math.max(0, 8 - _gap)
    color: Theme.fg3
    font.family: Theme.fontText
    font.pixelSize: Theme.fsSmall
    font.weight: Font.DemiBold
    elide: Text.ElideRight
}
