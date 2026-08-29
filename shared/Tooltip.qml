import QtQuick
import Quickshell
import Quickshell.Widgets

// Small reusable hover tooltip anchored below a bar module, similar in
// spirit to waybar's built-in module tooltips.
PopupWindow {
    id: popup

    required property Item anchorItem
    required property var theme
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
    visible: show && text.length > 0

    Rectangle {
        id: content
        anchors.fill: parent
        color: "#1e1e1e"
        border.color: popup.theme.accent
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
            color: popup.theme.groupText
            font.family: popup.theme.fontFamily
            font.pixelSize: popup.theme.fontSize
        }
    }

    implicitWidth: Math.min(label.implicitWidth, maxWidth) + 20
    implicitHeight: label.implicitHeight + 16
}
