pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations

// Faster FrameSpring tuning for Workspaces.qml, whose pill width, delegate
// widths and sliding selection indicator all have to stay in sync. Bind to
// `.value` and set `to`, as with any FrameSpring.
FrameSpring {
    stiffness: Theme.frameSpringWorkspaceStiffness
    damping: Theme.frameSpringWorkspaceDamping
    mass: Theme.frameSpringWorkspaceMass
}
