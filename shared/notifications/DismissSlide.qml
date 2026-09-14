pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.shared.notifications

// The control centre's dismissal gesture: a short wind-up to the left, then a
// slide off the panel's right edge. A toast's exit without the plate stages
// around it (see NotificationPopupWindow.qml) — the caller applies `value` as
// a Translate and does the actual dismissing from `finished`.
QtObject {
    id: root

    // How far right of its resting place the item is clear of the surface.
    required property real travel
    // How far left it pulls first. Smaller than the toasts' popupBump, most of
    // which is cancelled by the plate collapsing the other way underneath it —
    // here the whole of it is seen.
    property real bump: NotificationTheme.listDismissBump

    readonly property real value: slide.value
    // Latched, so start() is idempotent: a second click on a card already
    // leaving is not a second gesture.
    property bool active: false
    // Latched when the wind-up has reached its bump height.
    property bool wound: false

    signal finished

    function start() {
        if (root.active)
            return;
        root.active = true;
        // Aimed just past the bump, which the latch below stops it at: a spring
        // decelerates into its target, so the hop arrives near rest and the
        // drop turns it around instead of yanking it out of a full-speed run.
        slide.retarget(-root.bump * 1.2);
    }

    property FrameSpring spring: FrameSpring {
        id: slide
        // Stiff and critically damped under the wind-up, so it covers its
        // distance quickly *and* arrives; soft enough under the drop not to
        // snatch. Same pair a toast's exit rides.
        stiffness: root.wound ? 72 : 455
        damping: root.wound ? 13.4 : 32.9
        onValueChanged: {
            if (!root.active)
                return;
            if (!root.wound) {
                if (slide.value <= -root.bump) {
                    root.wound = true;
                    // Aimed past the edge rather than at it: the last sliver of
                    // a card creeping away reads as an ease-out on an exit.
                    slide.retarget(root.travel * 1.5);
                }
            } else if (slide.value >= root.travel) {
                // Parks the spring the moment the card is clear; settling is
                // what fires `finished`.
                slide.snapTo(root.travel);
            }
        }
        onRunningChanged: if (!slide.running && root.wound)
            root.finished()
    }
}
