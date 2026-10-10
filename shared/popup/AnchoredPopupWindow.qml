pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.shared

// Base type for a PopupWindow anchored below a bar module: horizontally
// centered on it, 4px gap, sliding to stay on-screen. Shared by HoverPopup and
// Tooltip, which differ only in *when* they're visible, not in this math.
PopupWindow {
    id: popup

    required property Item anchorItem

    // Set by a subtype instead of implicitWidth/implicitHeight. The surface
    // rounds it up onto the device pixel grid, so it may end up a few px
    // larger (Screens.snapSurface()).
    property real wantedWidth: 0
    property real wantedHeight: 0
    // Transparent room below the wanted height, for a subtype that animates
    // its plate past its resting size: a window clips its contents.
    property real slackHeight: 0

    // Untyped: the cast to QsWindow would read null for an anchor inside a
    // PopupWindow, which isn't one.
    readonly property var _barWindow: popup.anchorItem.QsWindow.window
    // The bar's, not our own `screen`, which isn't the output the popup is
    // on (notes/quickshell-quirks.md).
    readonly property ShellScreen _barScreen: popup._barWindow?.screen ?? null

    implicitWidth: Screens.snapSurface(popup.wantedWidth, popup._barScreen)
    // The wanted height on the device grid: where a plate filling it rests.
    readonly property real restHeight: Screens.snapSurface(popup.wantedHeight, popup._barScreen)
    // Two on-grid lengths, so their sum is too.
    implicitHeight: popup.restHeight + Screens.snapSurface(popup.slackHeight, popup._barScreen)

    anchor {
        window: popup._barWindow
        adjustment: PopupAdjustment.Slide
        // No Left/Right edge on purpose: Quickshell then centers on the anchor
        // rect and recomputes on every reposition, including ones caused by the
        // popup's own width changing. A hand-rolled centering offset would be
        // evaluated once and go stale.
        gravity: Edges.Bottom
        edges: Edges.Bottom

        // pos is the anchor module's bottom-center point, plus the gap.
        onAnchoring: {
            const pos = popup.anchorItem.QsWindow.contentItem.mapFromItem(popup.anchorItem, popup.anchorItem.width / 2, popup.anchorItem.height + 4);
            anchor.rect.x = pos.x;
            anchor.rect.y = pos.y;
        }
    }

    // A new anchor item doesn't reposition on its own (only a resize or move
    // does), so Tray's shared tooltip hopping icons would stay put.
    onAnchorItemChanged: anchor.updateAnchor()

    color: "transparent"
}
