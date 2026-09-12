pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations

// FrameSpring preconfigured for press feedback: bind a MouseArea's `pressed`
// to `pressed` and the item's `scale` to `.value`. Shrinks while held, springs
// back on release, so every clickable shares one feel.
FrameSpring {
    // Explicit, not FrameSpring's default 0: `to` only snaps at
    // Component.onCompleted, and a button at scale 0 until then pops in.
    value: 1

    property bool pressed: false
    property real pressedScale: 0.88

    to: pressed ? pressedScale : 1

    // Theme.springEpsilon is pixel-scale; the whole press travel is ~0.12, so
    // retarget() would see this as already settled and never start it.
    epsilon: 0.002
}
