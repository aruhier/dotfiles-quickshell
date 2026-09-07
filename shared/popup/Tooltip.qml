pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup

// Small hover tooltip anchored below a bar module. No grace-period timer,
// unlike HoverPopup: it's plain text with nothing to move the cursor onto, so
// it closes immediately.
AnchoredPopupWindow {
    id: popup

    property string text: ""
    property bool show: false
    property int maxWidth: 480

    visible: show && text.length > 0

    Rectangle {
        anchors.fill: parent
        color: "#1e1e1e"
        border.color: Theme.accent
        border.width: 1
        radius: 6

        StyledText {
            id: label
            anchors.fill: parent
            anchors.margins: 10
            text: popup.text
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            color: Theme.groupText
            font.pixelSize: Theme.fontSize
        }
    }

    // Math.ceil, not round/floor: a PopupWindow's surface is integer-pixel,
    // and rounding label metrics down clips a sub-pixel sliver off the border.
    implicitWidth: Math.ceil(Math.min(label.implicitWidth, maxWidth) + 20)
    implicitHeight: Math.ceil(label.implicitHeight + 16)
}
