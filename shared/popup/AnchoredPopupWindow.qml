pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Base type for a PopupWindow anchored below a bar module: horizontally
// centered on it, 4px gap, sliding to stay on-screen. Shared by HoverPopup and
// Tooltip, which differ only in *when* they're visible, not in this math.
PopupWindow {
    id: popup

    required property Item anchorItem

    anchor {
        window: popup.anchorItem.QsWindow.window
        adjustment: PopupAdjustment.Slide
        // No Left/Right edge on purpose: Quickshell then centers on the anchor
        // rect and recomputes on every reposition, including ones caused by the
        // popup's own width changing. A hand-rolled centering offset would be
        // evaluated once and go stale.
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
