import QtQuick
import Quickshell
import Quickshell.Widgets

// Base type for a PopupWindow anchored just below a bar module, horizontally
// centered on the module (+ 4px gap below it), sliding to stay on-screen.
// Shared by HoverPopup.qml and Tooltip.qml — they differ only in *when*
// they're visible (grace-period close vs immediate, see HoverPopup.qml's
// header comment), not in this positioning math.
PopupWindow {
    id: popup

    required property Item anchorItem

    anchor {
        window: popup.anchorItem.QsWindow.window
        adjustment: PopupAdjustment.Slide
        // No Left/Right in either: Quickshell's PopupPositioner reads that
        // as "use the anchor rect's/gravity's horizontal center" (see
        // popupanchor.cpp's calcEffectiveX), computed live off the popup's
        // *current* window width on every reposition — including ones
        // triggered by the popup's own width changing later (e.g. Tooltip
        // text changing while shown). A hand-rolled `rect.x - width / 2`
        // offset here would only be evaluated once, at anchoring time, and
        // go stale on any later resize.
        gravity: Edges.Bottom
        edges: Edges.Bottom

        // pos is the anchor module's bottom-center point.
        onAnchoring: {
            const pos = popup.anchorItem.QsWindow.contentItem.mapFromItem(popup.anchorItem, popup.anchorItem.width / 2, popup.anchorItem.height + 4);
            anchor.rect.x = pos.x;
            anchor.rect.y = pos.y;
        }
    }

    color: "transparent"
}
