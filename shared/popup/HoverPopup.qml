pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.popup
import qs.themes

// Base type for a hover-triggered popup below a bar module: chrome, the close
// grace timer and PopupCoordinator registration on top of
// AnchoredPopupWindow's anchor math. A module supplies content as default
// children, its HoverPopupArea sets `anchorHovered`, and it sets its own
// implicitWidth/implicitHeight. Tooltip.qml is the other kind — declarative
// `show`, no grace period — and shares only AnchoredPopupWindow.
AnchoredPopupWindow {
    id: popup

    property int cornerRadius: 10
    property int padding: 14
    property int hideDelay: 200

    default property alias content: contentItem.data

    // Written by HoverPopupArea; the module's side of the hover.
    property bool anchorHovered: false

    // Is the cursor anywhere that should keep this popup up. Derived, not
    // stored, so the two halves can report in either order.
    readonly property bool hovered: anchorHovered || surface.hovered

    property bool _open: false

    onHoveredChanged: {
        if (hovered) {
            hideTimer.stop();
            PopupCoordinator.activate(popup);
            _open = true;
        } else {
            hideTimer.restart();
        }
    }

    // Closes immediately, no grace period — called on takeover by
    // PopupCoordinator and by HoverPopupArea.cancel(). Deactivates too: its
    // LazyLoader may tear it down right after, and a coordinator still
    // pointing here would call close() on a destroyed object.
    function close() {
        hideTimer.stop();
        _open = false;
        PopupCoordinator.deactivate(popup);
    }

    // Grace for the cursor to cross the gap between module and popup (or
    // back) without the popup closing under it.
    Timer {
        id: hideTimer
        interval: popup.hideDelay
        onTriggered: {
            if (!popup.hovered)
                popup.close();
        }
    }

    visible: _open

    Rectangle {
        anchors.fill: parent
        color: Theme.popupBg
        border.color: Theme.accent
        border.width: 1
        radius: popup.cornerRadius

        // A HoverHandler on the surface, not a MouseArea behind contentItem:
        // Qt delivers hover to an accepting item's ancestors but not to items
        // behind it, so a hover-tracked child in the content would close the
        // popup under the cursor.
        HoverHandler {
            id: surface
        }

        Item {
            id: contentItem
            anchors.fill: parent
            anchors.margins: popup.padding
        }
    }
}
