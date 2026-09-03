import QtQuick
import ".."

// Faster FrameSpring tuning used only by Workspaces.qml, where the pill
// width, delegate width, and sliding selection indicator all need to stay in
// sync with each other (see Theme.qml's frameSpringWorkspaceStiffness/
// frameSpringWorkspaceDamping/frameSpringWorkspaceMass) — the FrameSpring
// equivalent of WorkspaceSpring.qml, for the same "capped near 60Hz" reason
// FrameSpring.qml itself documents. Bind to `.value` and call `retarget()`
// explicitly; unlike Behavior/WorkspaceSpring this isn't declarative.
FrameSpring {
    stiffness: Theme.frameSpringWorkspaceStiffness
    damping: Theme.frameSpringWorkspaceDamping
    mass: Theme.frameSpringWorkspaceMass
}
