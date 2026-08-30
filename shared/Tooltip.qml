import QtQuick
import Quickshell
import Quickshell.Widgets

// Small reusable hover tooltip anchored below a bar module, similar to
// waybar's built-in module tooltips.
PopupWindow {
    id: popup

    required property Item anchorItem
    property string text: ""
    property bool show: false
    property int maxWidth: 480

    anchor {
        window: anchorItem.QsWindow.window
        adjustment: PopupAdjustment.Slide
        gravity: Edges.Bottom | Edges.Right
        edges: Edges.Bottom | Edges.Left

        onAnchoring: {
            const pos = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, 0, anchorItem.height + 4);
            anchor.rect.x = pos.x;
            anchor.rect.y = pos.y;
        }
    }

    color: "transparent"
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

        Text {
            renderType: Text.NativeRendering
            id: label
            anchors.fill: parent
            anchors.margins: 10
            text: popup.text
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            color: Theme.groupText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    // Math.ceil, not round/floor: a PopupWindow's surface is integer-pixel,
    // and rounding label metrics down clips the border's far edge by a
    // sub-pixel sliver.
    implicitWidth: Math.ceil(Math.min(label.implicitWidth, maxWidth) + 20)
    implicitHeight: Math.ceil(label.implicitHeight + 16)
}
