import QtQuick
import Quickshell
import Quickshell.Widgets

// Base type for a PopupWindow anchored just below a bar module (module's
// bottom-left corner + 4px gap), sliding to stay on-screen. Shared by
// HoverPopup.qml and Tooltip.qml — they differ only in *when* they're
// visible (grace-period close vs immediate, see HoverPopup.qml's header
// comment), not in this positioning math.
PopupWindow {
    id: popup

    required property Item anchorItem

    anchor {
        window: popup.anchorItem.QsWindow.window
        adjustment: PopupAdjustment.Slide
        gravity: Edges.Bottom | Edges.Right
        edges: Edges.Bottom | Edges.Left

        onAnchoring: {
            const pos = popup.anchorItem.QsWindow.contentItem.mapFromItem(popup.anchorItem, 0, popup.anchorItem.height + 4);
            anchor.rect.x = pos.x;
            anchor.rect.y = pos.y;
        }
    }

    color: "transparent"
}
