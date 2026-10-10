pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.shared
import qs.shared.animations
import qs.shared.popup
import qs.themes

// Base type for a hover-triggered popup below a bar module: chrome, the
// unfold out of the bar and fold back, the close grace timer and
// PopupCoordinator registration on top of AnchoredPopupWindow's anchor math. A module supplies content as default
// children, its HoverPopupArea sets `anchorHovered`, and it sets its own
// wantedWidth/wantedHeight. Tooltip.qml is the other kind — declarative
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

    // Hovered, or within the grace period after.
    property bool _open: false
    // Mapped: open, or folding away after a hover-out. Cleared when the fold
    // parks, or outright by close().
    property bool _shown: false
    // What a subtype narrows its own `visible` with.
    readonly property bool isShown: _shown

    // Emitted once the popup is gone; HoverPopupArea tears it down on it.
    signal dismissed()

    onHoveredChanged: {
        if (hovered) {
            hideTimer.stop();
            PopupCoordinator.activate(popup);
            _open = true;
            _shown = true;
        } else {
            hideTimer.restart();
        }
    }

    // Closes immediately, no grace period and no fold — called on takeover by
    // PopupCoordinator and by HoverPopupArea.cancel(), where the next popup or
    // the click is the feedback. Deactivates too: its LazyLoader may tear it
    // down right after, and a coordinator still pointing here would call
    // close() on a destroyed object.
    function close() {
        hideTimer.stop();
        _open = false;
        _shown = false;
        unfold.snapTo(popup.collapsedHeight);
        PopupCoordinator.deactivate(popup);
        popup.dismissed();
    }

    // Torn down without close(): a previewed workspace destroyed with its
    // last window. A dead `var` owner reads null but never notifies, so the
    // bar would hold its peek, never auto-hiding, until the next popup.
    Component.onDestruction: PopupCoordinator.deactivate(popup)

    // Grace for the cursor to cross the gap between module and popup (or
    // back) without the popup closing under it. Then folds rather than
    // closing: the coordinator stays pointed here until the fold parks, so
    // another popup opening mid-fold still takes over with close().
    Timer {
        id: hideTimer
        interval: popup.hideDelay
        onTriggered: {
            if (!popup.hovered)
                popup._open = false;
        }
    }

    visible: isShown

    // The plate unfolds out of the bar: its height springs from a strip as
    // tall as its two corners to the resting height, and folds back up on a
    // hover-out. The content stays laid out at full size and is clipped, so
    // nothing inside re-lays out per frame. See notes/popups.md.
    readonly property real collapsedHeight: 2 * popup.cornerRadius
    readonly property real _travel: popup.restHeight - popup.collapsedHeight
    // Room for the open's overshoot, 5.4% of the travel at its damping.
    slackHeight: Math.ceil(0.06 * popup._travel)

    readonly property real opened: Ramp.ramp(unfold.value, popup.collapsedHeight, popup.restHeight)

    // Aimed half the travel past the strip, so the fold doesn't decelerate
    // into the bar, and parked as it reaches it. At least a strip's height
    // past: aimed at the strip itself, the fold would never start, so never
    // park and dismiss.
    readonly property real _foldAim: popup.collapsedHeight - Math.max(0.5 * popup._travel, popup.collapsedHeight)

    // Set by the window's first frame. Until then the plate holds at the strip,
    // or the open starts with a jump: the frame takes long enough to build
    // for the spring to be well under way before anything is on screen.
    property bool _presented: false
    Connections {
        target: plate.Window.window
        enabled: !popup._presented
        function onFrameSwapped() {
            popup._presented = true;
        }
    }

    // Plate height in px. Snaps to the strip on creation, before any hover.
    // Content arriving while open (the weather spinner giving way to the
    // forecast) moves `restHeight`, and grows the plate on the same spring.
    FrameSpring {
        id: unfold
        to: popup._open ? (popup._presented ? popup.restHeight : popup.collapsedHeight) : popup._shown ? popup._foldAim : popup.collapsedHeight

        // Under damped open (ζ ≈ 0.68): the run past the resting height and
        // the settle back is the arrival. Just past critical shut (ζ ≈ 1.08),
        // so the fold reads as one stroke up with no wobble before it parks.
        stiffness: popup._open ? 230 : 260
        damping: popup._open ? 16 : 27

        // `_shown` first: snapTo() changes `value` again, re-entering here.
        onValueChanged: {
            if (!popup._open && popup._shown && value <= popup.collapsedHeight) {
                popup._shown = false;
                snapTo(popup.collapsedHeight);
                PopupCoordinator.deactivate(popup);
                popup.dismissed();
            }
        }
    }

    // Only the plate's resting rect takes input: the slack below it is
    // transparent and must not swallow clicks on the window underneath.
    mask: Region {
        width: popup.width
        height: popup.restHeight
    }

    Rectangle {
        id: plate
        width: parent.width
        // Snapped, so the bottom border stays one solid row while it moves.
        height: Screens.snap(Math.max(popup.collapsedHeight, unfold.value), popup._barScreen)
        clip: true
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

        // The wanted size, not the surface's: the device-grid slack becomes
        // bottom/right padding instead of stretching the layout inside.
        // Plain opacity, no layer: a layered subtree is resampled and its
        // text blurs (notes/text.md). Never `visible: false` at opacity 0, as
        // the OSD's detail is: a ScreencopyView in the content reads its
        // effective visibility and would only start capturing halfway open.
        Item {
            id: contentItem
            x: popup.padding
            y: popup.padding
            width: popup.wantedWidth - 2 * popup.padding
            height: popup.wantedHeight - 2 * popup.padding
            opacity: Ramp.reveal(popup.opened)
        }
    }
}
