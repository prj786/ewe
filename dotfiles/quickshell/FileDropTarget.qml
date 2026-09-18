import QtQuick
import QtQuick.Dialogs

// FileDropTarget — the file drop zone (design system: File drop zone), and
// the ONE image/video input plumbing, used by Settings → Wallpaper and
// Settings → User (avatar):
//   * a drop zone: text/uri-list drags of image (and, with acceptVideo,
//     video) files, with hover and drag feedback;
//   * click (or calling browse() from outside, e.g. a "Browse files…" pill)
//     opens the XDG portal file chooser. Both require the containing window
//     to be a real xdg-toplevel — see Settings.qml.
//
//   zone      3 × control2xl (144) tall, spaceMd of padding, surfaceSunken
//             behind a borderWidth1 DASHED borderStrong outline on the
//             radiusRounded corner (Canvas: a Rectangle cannot dash)
//   content   an iconXl glyph in textMuted, the title in body-strong, the
//             hint in the caption style
//   hover     the outline turns textMuted
//   dragging  a SOLID focusRing outline on an accentSubtle ground, and the
//             title says what will happen ("Release to add")
//   error     a danger outline on dangerSubtle
//
// Emits picked(path) with a canonical, percent-decoded absolute path (spaces
// and non-ASCII are fine).
Rectangle {
    id: root

    property bool acceptVideo: false
    property string label: "Drop an image here — or click to browse"
    property string dragLabel: "Release to add"
    property string hint: ""
    property string error: ""            // a reason; shows the danger state
    property string dialogTitle: "Choose image"
    signal picked(string path)
    readonly property bool hovering: drop.containsDrag

    implicitHeight: 3 * Theme.control2xl
    radius: Theme.radiusRounded
    color: root.error !== "" ? Theme.dangerSubtle
         : root.hovering ? Theme.accentSubtle : Theme.surfaceSunken
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

    readonly property color lineColor: root.error !== "" ? Theme.danger
                                     : root.hovering ? Theme.focusRing
                                     : zoneMa.containsMouse ? Theme.textMuted : Theme.borderStrong
    readonly property color _ink: root.error !== "" ? Theme.danger
                                : root.hovering ? Theme.accentText : Theme.textMuted

    readonly property var _imageExts: ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
    readonly property var _videoExts: ["mp4", "webm", "mkv", "mov", "avi", "m4v"]

    function browse() { dlg.open() }
    function urlToPath(u) { return decodeURIComponent(String(u).replace(/^file:\/\//, "")) }
    function extOk(p) {
        var e = String(p).split(".").pop().toLowerCase()
        return _imageExts.indexOf(e) >= 0 || (acceptVideo && _videoExts.indexOf(e) >= 0)
    }
    function _accept(u) { var p = urlToPath(u); if (extOk(p)) root.picked(p) }

    // the dashed outline — Rectangle's border cannot dash, so it is drawn
    // here; a drag over the zone makes it solid
    Canvas {
        id: edge
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = Theme.borderWidth1
            ctx.lineWidth = w
            ctx.strokeStyle = root.lineColor
            ctx.setLineDash(root.hovering ? [] : [2 * Theme.spaceXs, Theme.spaceXs])
            ctx.beginPath()
            ctx.roundedRect(w / 2, w / 2, width - w, height - w, root.radius, root.radius)
            ctx.stroke()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onLineColorChanged() { edge.requestPaint() }
            function onHoveringChanged() { edge.requestPaint() }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.spaceMd
        spacing: Theme.spaceXs
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.icDownload
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconXl
            color: root._ink
            bottomPadding: Theme.spaceXs
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.error !== "" ? root.error : root.hovering ? root.dragLabel : root.label
            color: root.error !== "" ? Theme.danger : Theme.textPrimary
            font.family: Theme.type.bodyStrong.family
            font.pixelSize: Theme.type.bodyStrong.size
            font.weight: Theme.type.bodyStrong.weight
            elide: Text.ElideRight
        }
        Text {
            visible: root.hint !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.hint
            color: Theme.textMuted
            font.family: Theme.type.caption.family
            font.pixelSize: Theme.type.caption.size
            wrapMode: Text.Wrap
        }
    }
    MouseArea { id: zoneMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.browse() }
    DropArea {
        id: drop
        anchors.fill: parent
        onEntered: function (drag) {
            if (!drag.hasUrls || !drag.urls.length || !root.extOk(root.urlToPath(drag.urls[0])))
                drag.accepted = false
        }
        onDropped: function (d) { if (d.hasUrls && d.urls.length) root._accept(d.urls[0]) }
    }
    FileDialog {
        id: dlg
        title: root.dialogTitle
        nameFilters: root.acceptVideo
            ? ["Images & video (*.png *.jpg *.jpeg *.webp *.bmp *.gif *.mp4 *.webm *.mkv *.mov *.m4v)", "All files (*)"]
            : ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.gif)", "All files (*)"]
        onAccepted: root._accept(selectedFile)
    }
}
