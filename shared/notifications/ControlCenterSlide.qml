pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations
import qs.shared.notifications

// The control centre's slide, staged the way the OSD pill and the toasts are:
// four stages on one spring, two latches, every stage critically damped — sweep
// in, ease into a bump past the resting place, settle back out of it, and on
// the way out wind up *onto* the screen before dropping off the edge.
//
// One spring rather than one per stage, so a gesture interrupted mid-flight —
// closing while still arriving — picks the panel up where it actually is
// instead of jumping. That, and the fact that the panel is placed by a margin
// rather than by a Translate, is why this is not DismissSlide.qml, which the
// toasts and the control-centre rows leave by. See notes/panels.md.
//
// The caller binds `margin` to the panel's rightMargin and drives the gesture
// with open() / close(); `finished` is the exit landing, which is what unmaps
// the window.
QtObject {
    id: root

    // Where the panel rests, and where it is clear of the screen, as
    // rightMargin values. A bigger margin is further left, so both bumps — the
    // arrival's, past the screen edge, and the exit's wind-up, back onto the
    // screen — sit *above* `resting`, and the drop far below it.
    required property real resting
    required property real closed
    // Null degrades to scale 1, like everything else that asks Screens.
    property var screen: null

    // The exit has landed and the caller can unmap.
    signal finished

    // Each stage is aimed past the line that ends it and caught there by a
    // latch: a spring decelerates into its target, so aiming past the bump
    // arrives at it slowly and releases from near rest, where a spring aimed
    // *at* it would still be at full speed. That is the whole difference
    // between this and one under damped spring, which crosses its resting line
    // fast and rings back.
    readonly property real bumpLine: root.resting + NotificationTheme.controlCenterBump
    readonly property real bumpAim: root.resting + NotificationTheme.controlCenterBump * 1.2
    readonly property real windUpLine: root.resting + NotificationTheme.controlCenterDismissBump
    readonly property real windUpAim: root.resting + NotificationTheme.controlCenterDismissBump * 1.2
    // Aimed past the edge rather than at it: the last sliver of a panel
    // creeping away reads as an ease-out on an exit.
    readonly property real dropAim: root.closed - (root.resting - root.closed) * 0.5

    // Which half of the gesture is running, and the two latches. Latched
    // rather than compared, because the spring crosses each line and comes
    // back over it.
    property bool closing: false
    property bool bumped: false
    property bool wound: false

    function open() {
        root.closing = false;
        root.bumped = false;
        spring.retarget(root.bumpAim);
    }

    function close() {
        root.closing = true;
        root.wound = false;
        spring.retarget(root.windUpAim);
    }

    readonly property real devicePixel: 1 / Screens.scaleFor(root.screen)

    // The rendered margin. Snapped over the *landing* only — the last couple
    // of device pixels of the settle — because glyph origins are rounded to
    // whole device pixels while the panel's plate is resampled continuously,
    // so there the text takes its final step alone while the panel is creeping
    // too slowly to read as moving, and that looks like the text shifting
    // inside its card. Snapped, plate and text step together. Anywhere else it
    // would be the whole gesture advancing a device pixel at a time, which
    // reads as stepping — see notes/text.md for both halves.
    readonly property bool landing: !root.closing && root.bumped && Math.abs(spring.value - root.resting) <= 2 * root.devicePixel
    readonly property real margin: root.landing ? Screens.snap(spring.value, root.screen) : spring.value

    property FrameSpring spring: FrameSpring {
        id: spring
        // The sweep is soft enough to read at 500px of travel, the settle
        // stiffer since it only has the bump to undo, and the exit's pair are
        // the toasts' own — the wind-up stiff so it covers its distance *and*
        // arrives, the drop soft enough not to snatch. Scale a pair to change
        // the pace, never the stiffness alone; the knob is in notes/osd.md.
        // The opening pair have been through it once, at 1.15.
        stiffness: root.closing ? (root.wound ? 72 : 455) : (root.bumped ? 345 : 227)
        damping: root.closing ? (root.wound ? 13.4 : 32.9) : (root.bumped ? 28.8 : 23.3)
        Component.onCompleted: snapTo(root.closed)
        onValueChanged: {
            if (root.closing) {
                if (!root.wound) {
                    if (value >= root.windUpLine) {
                        root.wound = true;
                        retarget(root.dropAim);
                    }
                } else if (value <= root.closed) {
                    // Parked the moment the panel is clear; settling is what
                    // unmaps the window.
                    snapTo(root.closed);
                }
            } else if (!root.bumped) {
                if (value >= root.bumpLine) {
                    root.bumped = true;
                    retarget(root.resting);
                }
            } else if (Math.abs(value - root.resting) <= 0.5 * root.devicePixel) {
                // Parked once the rendered position can no longer change.
                // FrameSpring's stop condition compares a velocity in px/s
                // against a pixel epsilon, so a critically damped settle goes
                // on integrating for ~130ms after it has visibly arrived —
                // frames that can only produce the sub-pixel drift above.
                snapTo(root.resting);
            }
        }
        onRunningChanged: if (!running && root.closing)
            root.finished()
    }
}
