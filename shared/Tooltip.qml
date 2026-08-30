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
    // Stay open while the cursor is over the tooltip itself, not just the
    // anchor. A plain `show || contentHover.containsMouse` OR doesn't work
    // for this: the anchor and the popup are separate surfaces 4px apart
    // (see onAnchoring below), so the instant the cursor leaves the anchor,
    // `show` goes false and the popup (having no idea the cursor is still
    // travelling toward it) unmaps itself before the cursor ever reaches
    // `contentHover` — which then never gets a chance to see it. Fixed with
    // a short grace-period timer instead: closing is delayed, not
    // immediate, so a normal-speed cursor crossing that 4px gap re-enters
    // (via `show` or `contentHover`) well before the timer fires.
    property bool _open: false
    visible: _open && text.length > 0

    onShowChanged: {
        if (show) {
            hideTimer.stop();
            _open = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 200
        onTriggered: {
            if (!popup.show && !contentHover.containsMouse)
                popup._open = false;
        }
    }

    Rectangle {
        id: content
        anchors.fill: parent
        color: "#1e1e1e"
        border.color: popup.theme.accent
        border.width: 1
        radius: 6

        MouseArea {
            id: contentHover
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: {
                if (containsMouse) {
                    hideTimer.stop();
                    popup._open = true;
                } else {
                    hideTimer.restart();
                }
            }
        }

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
