pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup

// Small reusable hover tooltip anchored below a bar module.
AnchoredPopupWindow {
    id: popup

    property string text: ""
    property bool show: false
    property int maxWidth: 480

    // No grace-period timer here (unlike Weather.qml's popup): plain text,
    // nothing to move the cursor onto, so it should close immediately.
    visible: show && text.length > 0

    Rectangle {
        id: content
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
    // and rounding label metrics down clips the border's far edge by a
    // sub-pixel sliver.
    implicitWidth: Math.ceil(Math.min(label.implicitWidth, maxWidth) + 20)
    implicitHeight: Math.ceil(label.implicitHeight + 16)
}
