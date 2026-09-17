pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations

// Faster FrameSpring tuning for Workspaces.qml, whose pill width, delegate
// widths and selection indicator move together. Used like any FrameSpring.
//
// Same damping ratio as FrameSpring's defaults (ζ ≈ 1.05), roughly 2x the
// natural frequency. Don't damp it further — the leftover wobble is pixel
// rounding, handled in Workspaces.qml itself.
FrameSpring {
    stiffness: 920
    damping: 50
    mass: 0.6
}
