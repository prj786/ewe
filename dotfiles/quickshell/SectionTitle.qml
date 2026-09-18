import QtQuick

// SectionTitle — the heading that names a group of settings or list items
// (design system: Section header). Two forms:
//
//   overline (default)  the `overline` type style in textMuted, for a short
//                       label directly above a list well
//   title               h4 (15px, semibold) in textPrimary, for a section of
//                       a page
//
// Spacing is the card's: spaceMd + spaceS (24) above, spaceS (8) below, and
// nothing above the first heading in a pane, so every pane's first heading
// lands on the same baseline. The paddings subtract the parent Column's own
// spacing, so the visual gaps come out at the card's figures.
//
// SENTENCE CASE, never uppercase: Qt would turn Georgian Mkhedruli into
// Mtavruli. The overline style carries the letter spacing and leaves the
// letters alone — that is what the reference CSS's `text-transform` is for
// here, and it does not apply to this desktop.
//     SectionTitle { text: "Output" }
Text {
    id: st
    property string variant: "overline"        // overline · title
    property bool first: st.parent ? (st.parent.children.length > 0 && st.parent.children[0] === st) : true
    readonly property var _style: st.variant === "title" ? Theme.type.h4 : Theme.type.overline
    readonly property int _gap: st.parent && st.parent.spacing !== undefined ? st.parent.spacing : 0
    topPadding: st.first ? 0 : Math.max(0, Theme.spaceMd + Theme.spaceS - _gap)
    bottomPadding: Math.max(0, Theme.spaceS - _gap)
    color: st.variant === "title" ? Theme.textPrimary : Theme.textMuted
    font.family: _style.family
    font.pixelSize: _style.size
    font.weight: _style.weight
    font.letterSpacing: _style.letterSpacing
    font.capitalization: Font.MixedCase
    elide: Text.ElideRight
}
