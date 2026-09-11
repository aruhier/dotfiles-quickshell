pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup

// Base type for a hover-triggered popup below a bar module: adds the
// background chrome, the close grace timer and PopupCoordinator registration
// on top of AnchoredPopupWindow's anchor math, so every popup gets close() and
// mutual exclusion for free. A module supplies content as default children,
// its HoverPopupArea sets `anchorHovered`, and it still sets
// implicitWidth/implicitHeight itself.
//
// Tooltip.qml shares only AnchoredPopupWindow, not this: it's driven by a
// declarative `show` bool and closes with no grace period, a different enough
// contract that forcing it onto this API would be a behavior change.
AnchoredPopupWindow {
    id: popup

    property int cornerRadius: 10
    property int padding: 14
    property int hideDelay: 200

    default property alias content: contentItem.data

    // Written by HoverPopupArea; the module's side of the hover.
    property bool anchorHovered: false

    // The one fact the open/close logic runs on: is the cursor anywhere that
    // should keep this popup up. Derived, not stored, so there is no copy of
    // the hover state to fall out of sync and no dependence on the order in
    // which the module and the surface report their halves.
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

    // Closes immediately, no grace period. Called by PopupCoordinator on the
    // previously-active popup when another takes over, and by
    // HoverPopupArea.cancel(). Deactivates too: a popup closed this way can be
    // torn down by its LazyLoader right after, and a coordinator still
    // pointing at it would later call close() on a destroyed object. (During
    // a takeover the coordinator overwrites activeOwner right after anyway.)
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

        // A HoverHandler on the surface itself, not a hover MouseArea laid
        // behind contentItem: Qt keeps delivering hover to an accepting item's
        // ancestors but stops at items behind it, so a hover-tracked child in
        // the content (Weather's refresh button) would have left a sibling
        // MouseArea un-hovered and closed the popup under the cursor. Same
        // shape as NotificationCard's whole-card handler over its CloseButton.
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
