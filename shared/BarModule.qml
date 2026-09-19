pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.themes

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

    // 6px each side.
    property real padding: 12

    // What to draw text in: the group's colour, handed down by ModuleLoader,
    // so a module reads against whichever pill it's placed in. A module that
    // paints its own chip picks its own pair instead.
    property color textColor: Theme.groupText

    // Set false to disappear entirely rather than shrink to zero width. A
    // plain bool that ModuleLoader reads, never read back through `visible`:
    // a Loader mirroring its item's `visible` deadlocks the first time it goes
    // false and can never observe a return to true. See AGENTS.md.
    //
    // Not mirrored onto this item's own `visible`: the loader hides it, and a
    // collapsing ModuleGroup keeps the loader shown so the module stays drawn
    // while the group shrinks over it — a `visible: contentVisible` here would
    // blank it a frame early.
    property bool contentVisible: true

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
