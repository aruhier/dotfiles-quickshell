pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations

// Faster FrameSpring tuning for Workspaces.qml, whose pill width, delegate
// widths and selection indicator move together. Used like any FrameSpring.
FrameSpring {
    stiffness: Theme.frameSpringWorkspaceStiffness
    damping: Theme.frameSpringWorkspaceDamping
    mass: Theme.frameSpringWorkspaceMass
}
