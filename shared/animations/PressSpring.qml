import QtQuick
import ".."

// FrameSpring preconfigured for press-feedback scale: bind a MouseArea's
// `pressed` to `pressed` here, and an item's `scale` to `.value`. Shrinks to
// `pressedScale` while held, springs back to 1 on release — same
// FrameAnimation-driven physics as the notification panel's slide-in, just
// applied to a scale instead of a margin. Used for every clickable
// notification action (dismiss, group close-all, expand/collapse) and every
// Mpris control button, so every action in shared/notifications/ shares one
// consistent bit of tactile feedback rather than each button reinventing it.
FrameSpring {
    id: root

    value: 1
    target: 1

    property bool pressed: false
    property real pressedScale: 0.88

    // Theme.springEpsilon (0.25) is tuned for pixel-scale springs (e.g. the
    // notification panel's ~300px slide) — on a 0..1 scale value, the whole
    // press travel (1 -> pressedScale, ~0.12) is smaller than that epsilon,
    // so retarget()'s isSettled() check would call it already-settled and
    // never flip `running` true, leaving the button visually stuck at
    // scale 1 on press. A much smaller epsilon here keeps the same
    // mass-spring-damper feel at the right units for a scale value.
    epsilon: 0.002

    onPressedChanged: retarget(pressed ? pressedScale : 1)
}
