pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.shared

// Base type for a bar module: owns the eased width, the bar-height sizing and
// the show/hide flag ModuleLoader reads, so a module file contains only what's
// specific to it. Two of the lines it replaces fail silently when forgotten
// (see FrameSpring's `to`), which is why this is a base type rather than a
// style rule.
//
// Not every module fits, and that's fine: Workspaces.qml rounds its spring
// output and drives five coupled springs off one SpringGroup, Privacy.qml
// springs its per-app icons rather than its own width. Both stay hand-rolled.
Item {
    id: module

    // What this module's content measures, before padding. implicitWidth is
    // derived from it — a module should never bind implicitWidth itself.
    property real contentWidth: 0

    // Total horizontal padding, 6px each side. Submap's accent pill is wider
    // on purpose.
    property real padding: 12

    // Set false to disappear entirely rather than shrink to zero width.
    //
    // A plain bool, never read back through `visible`: a Loader whose own
    // `visible` mirrors its item's `visible` deadlocks permanently the first
    // time it goes false, because Qt Quick cascades a false ancestor `visible`
    // into the child's getter and the binding can never observe a return to
    // true. ModuleLoader reads this instead. See AGENTS.md.
    property bool contentVisible: true
    visible: contentVisible

    // Deliberately not gated on contentVisible: a width binding that reads a
    // child's implicitWidth *and* is gated on the visibility condition can
    // leave visibility stuck. A hidden module just keeps a width; nothing
    // draws it, and the Loader excludes it from the row's spacing.
    readonly property real targetWidth: contentWidth + padding

    implicitWidth: widthSpring.value
    implicitHeight: Theme.barHeight
    clip: true

    FrameSpring {
        id: widthSpring
        to: module.targetWidth
    }
}
