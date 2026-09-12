pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.shared

// Base type for a bar module: owns the eased width, the bar-height sizing and
// the show/hide flag ModuleLoader reads, so a module file holds only what's
// specific to it. A base type rather than a style rule because two of the
// lines it replaces fail silently when forgotten (see FrameSpring's `to`).
// Workspaces.qml and Privacy.qml animate differently and stay hand-rolled.
Item {
    id: module

    // The content's own width, before padding. A module sets this and never
    // binds implicitWidth itself.
    property real contentWidth: 0

    // 6px each side. Submap's accent pill is wider on purpose.
    property real padding: 12

    // Set false to disappear entirely rather than shrink to zero width. A
    // plain bool that ModuleLoader reads, never read back through `visible`:
    // a Loader mirroring its item's `visible` deadlocks the first time it goes
    // false and can never observe a return to true. See AGENTS.md.
    property bool contentVisible: true
    visible: contentVisible

    // Not gated on contentVisible: a width binding that reads a child's
    // implicitWidth *and* the visibility condition can leave visibility stuck.
    // A hidden module keeps its width; nothing draws it either way.
    readonly property real targetWidth: contentWidth + padding

    implicitWidth: widthSpring.value
    implicitHeight: Theme.barHeight
    clip: true

    FrameSpring {
        id: widthSpring
        to: module.targetWidth
    }
}
