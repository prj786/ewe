import QtQuick

// QsField — the Text field box (design system: Text field, md): surfaceSunken
// behind a borderStrong outline that turns textMuted on hover, focusRing with
// focus and danger on an error. Put a QsFieldInput inside and bind `focused`
// to its activeFocus, so the input's id stays reachable from the page.
Rectangle {
    id: fd
    property bool focused: false
    property bool error: false
    width: parent ? parent.width : Theme.panelSm
    height: Theme.controlMd
    radius: Theme.radiusPrimary
    color: Theme.surfaceSunken
    border.color: fd.error ? Theme.danger : fd.focused ? Theme.focusRing
                : fdHover.hovered ? Theme.textMuted : Theme.borderStrong
    border.width: Theme.fieldBorderWidth
    HoverHandler { id: fdHover }
}
