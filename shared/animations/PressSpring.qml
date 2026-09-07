pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations

// FrameSpring preconfigured for press feedback: bind a MouseArea's `pressed`
// to `pressed`, and the item's `scale` to `.value`. Shrinks while held,
// springs back on release. Used by every clickable notification action and
// Mpris control, so they all share one tactile feel.
FrameSpring {
    // Explicit, not FrameSpring's default 0: `to` only snaps at
    // Component.onCompleted, and a button drawn at scale 0 for the frame
    // before that would visibly pop in.
    value: 1

    property bool pressed: false
    property real pressedScale: 0.88

    to: pressed ? pressedScale : 1

    // Theme.springEpsilon (0.25) is tuned for pixel-scale springs. The whole
    // press travel here is ~0.12, so that epsilon would make retarget() see
    // the spring as already settled and never start it — leaving the button
    // stuck at scale 1.
    epsilon: 0.002
}
