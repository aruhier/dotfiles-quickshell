pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.shared

// Base type for a bar module: owns the eased width, the bar-height sizing and
// the show/hide flag Bar.qml's ModuleLoader reads, so a module file contains
// only what's actually specific to it.
//
// Before this type each module opened with the same six lines — a targetWidth
// binding, `implicitWidth: widthSpring.value`, `implicitHeight`, `clip`, a
// FrameSpring with a snapTo in Component.onCompleted, and an onTargetWidthChanged
// retarget — plus the same paragraph of comment explaining why the spring is a
// FrameSpring. Two of those lines fail silently when forgotten (see
// FrameSpring's `to`), which is the real reason this is a base type rather
// than a style rule in AGENT.md.
//
// Not every module fits, and that's fine — a base type doesn't have to be
// universal. Workspaces.qml rounds its spring output and drives five coupled
// springs off one shared SpringGroup; Privacy.qml springs its per-app icons
// rather than its own width. Both stay hand-rolled.
Item {
    id: module

    // What this module's content measures, before padding. The eased
    // implicitWidth is derived from it — a module should never bind
    // implicitWidth itself.
    property real contentWidth: 0

    // Total horizontal padding: 6px each side, the shared rule every module
    // in the bar follows. Submap's accent pill is wider on purpose.
    property real padding: 12

    // Set false to disappear entirely rather than shrink to zero width.
    //
    // A plain bool, never read back through `visible`: a Loader whose own
    // `visible` mirrors its loaded item's `visible` deadlocks permanently the
    // first time it goes false, because Qt Quick cascades a false ancestor
    // `visible` down into the child's own `visible` getter and the binding
    // can then never observe a return to true. See AGENT.md. ModuleLoader
    // reads this property instead, which is never the target of that cascade.
    property bool contentVisible: true
    visible: contentVisible

    // Deliberately not gated on contentVisible: a width binding that reads a
    // child's implicitWidth *and* is gated on the same condition as
    // visibility can leave visibility stuck. The module just keeps a width
    // while hidden; nothing draws it, and the Loader excludes it from the
    // row's spacing.
    readonly property real targetWidth: contentWidth + padding

    implicitWidth: widthSpring.value
    implicitHeight: Theme.barHeight
    clip: true

    FrameSpring {
        id: widthSpring
        to: module.targetWidth
    }
}
