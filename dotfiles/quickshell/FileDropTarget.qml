import QtQuick
import QtQuick.Dialogs

// FileDropTarget — the ONE image/video input plumbing, used by Settings →
// Wallpaper and Settings → User (avatar):
//   * a visible drop zone: accepts text/uri-list drags of image (and, with
//     acceptVideo, video) files, with hover feedback;
//   * click (or calling browse() from outside, e.g. a "Browse files…" pill)
//     opens the XDG portal file chooser. Both require the containing window to
//     be a real xdg-toplevel — see Settings.qml.
// Emits picked(path) with a canonical, percent-decoded absolute path (spaces
// and non-ASCII are fine).
Rectangle {
    id: root

    property bool acceptVideo: false
    property string label: "Drop an image here — or click to browse"
    property string dialogTitle: "Choose image"
    signal picked(string path)
    readonly property bool hovering: drop.containsDrag

    implicitHeight: 52
    radius: Theme.r(8)
    color: hovering ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : Theme.bg
    border.color: (hovering || zoneMa.containsMouse) ? Theme.accent : Theme.stroke
    border.width: Theme.borderThin
    Behavior on color { ColorAnimation { duration: 120 } }

    readonly property var _imageExts: ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
    readonly property var _videoExts: ["mp4", "webm", "mkv", "mov", "avi", "m4v"]

    function browse() { dlg.open() }
    function urlToPath(u) { return decodeURIComponent(String(u).replace(/^file:\/\//, "")) }
    function extOk(p) {
        var e = String(p).split(".").pop().toLowerCase()
        return _imageExts.indexOf(e) >= 0 || (acceptVideo && _videoExts.indexOf(e) >= 0)
    }
    function _accept(u) { var p = urlToPath(u); if (extOk(p)) root.picked(p) }

    Row {
        anchors.centerIn: parent; spacing: 9
        Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icDownload; font.family: Theme.fontIcons; font.pixelSize: 15; color: root.hovering ? Theme.accent : Theme.fgDim }
        Text { anchors.verticalCenter: parent.verticalCenter; text: root.label; color: root.hovering ? Theme.fg : Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
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
