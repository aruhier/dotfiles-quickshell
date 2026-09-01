import QtQuick
import ".."

// Faster spring tuning used only by Workspaces.qml, where the pill width,
// delegate width, and sliding selection indicator all need to stay in sync
// with each other (see Theme.qml's workspaceSpringSpring/workspaceSpringDamping).
// Use as `Behavior on <prop> { WorkspaceSpring {} }`.
SpringAnimation {
    spring: Theme.workspaceSpringSpring
    damping: Theme.workspaceSpringDamping
    epsilon: Theme.springEpsilon
}
