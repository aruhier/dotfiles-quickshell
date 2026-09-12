pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Repeater delegate for one named bar module: resolves the name via
// `resolveComponent` and lets a module hide entirely rather than shrink to
// zero width. Modules signal that through their own `contentVisible`, since a
// `visible: item.visible` binding here deadlocks the first time it goes false
// (see AGENTS.md); a module with nothing to hide just doesn't declare it.
//
// `modelData` must be `required`: without it Qt injects an ambient context
// property instead, and a bare `modelData` would resolve against an ancestor's
// (this bar's own screen, from shell.qml's Variants).
Loader {
    required property var resolveComponent
    required property string modelData

    sourceComponent: resolveComponent(modelData)
    // `active: false` alone still reserves RowLayout spacing on both sides.
    visible: item ? (item.contentVisible === undefined ? true : item.contentVisible) : false
    Layout.preferredWidth: (item as Item)?.implicitWidth ?? 0
}
