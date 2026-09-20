pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.themes

// The exit gesture both notification surfaces leave by: a short wind-up to the
// left, then a slide off the right edge. One spring, because the exit has to
// pick up wherever the arrival left the item — so a toast's entry rides it too
// (`playEntry`), while a control-centre row is simply there and starts at rest.
// The caller applies `value` as a Translate and does the actual dismissing from
// `finished`; the plate staging a toast wraps around this lives in
// NotificationPopupWindow.qml.
QtObject {
    id: root

    // How far right of its resting place the item is clear of the surface.
    required property real travel
    // How far left it pulls first. A toast's is far bigger than a panel row's:
    // most of it is cancelled by the plate collapsing the other way underneath
    // it, where a row has nothing moving under it. See notes/notifications.md.
    property real bump: NotificationTheme.bump

    // Whether the item slides in from `travel` on creation. Off by default.
    property bool playEntry: false
    // Soft and under damped (ζ ≈ 0.71), so the item bumps past its resting
    // place and settles back. Far softer than the exit's: an arriving toast is
    // off the surface for most of its travel, so a stiff spring would be most
    // of the way through before anything had been seen.
    property real entryStiffness: 58
    property real entryDamping: 8.4
    // How far out the arrival is "landed" — a latch, not a comparison, because
    // the slide crosses that line and comes back. The caller releases whatever
    // its second stage is off this, so it sits *into* the last of the slide
    // rather than at the resting line: started only once the slide had settled,
    // the two stages read as two gestures instead of one.
    property real entryLatchAt: 0
    property bool landed: !playEntry

    readonly property real value: slide.value
    // Latched, so start() is idempotent: a second click on a card already
    // leaving is not a second gesture, and a caller that has to watch two
    // conditions can call it from both.
    property bool active: false
    // Latched when the wind-up has reached its bump height.
    property bool wound: false

    signal finished

    // The arrival, on an item that already exists — a panel row whose group
    // just gained a notification, which the list keeps rather than rebuilds
    // (see NotificationGroupCard.qml). `playEntry` is the same slide for an
    // item built for it, read once by the spring's own Component.onCompleted.
    function enter() {
        if (root.active)
            return;
        root.landed = false;
        slide.snapTo(root.travel);
        slide.retarget(0);
    }

    function start() {
        if (root.active)
            return;
        root.active = true;
        // Aimed just past the bump, which the latch below stops it at: a spring
        // decelerates into its target, so the hop arrives near rest and the
        // drop turns it around instead of yanking it out of a full-speed run.
        // `bump` is the hop's height, this multiplier is its speed. Anything
        // further past was reported as "the transition between the bump and the
        // slide looks weird" — see notes/notifications.md.
        slide.retarget(-root.bump * 1.2);
    }

    property FrameSpring spring: FrameSpring {
        id: slide
        Component.onCompleted: if (root.playEntry) {
            snapTo(root.travel);
            retarget(0);
        }
        // Stiff and critically damped under the wind-up, so it covers its
        // distance quickly *and* arrives; soft enough under the drop not to
        // snatch.
        stiffness: !root.active ? root.entryStiffness : root.wound ? 72 : 455
        damping: !root.active ? root.entryDamping : root.wound ? 13.4 : 32.9
        onValueChanged: {
            if (!root.active) {
                if (!root.landed && slide.value <= root.entryLatchAt)
                    root.landed = true;
            } else if (!root.wound) {
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
