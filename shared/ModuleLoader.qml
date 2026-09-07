pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Repeater delegate for one named bar module: resolves the name to a Component
// via `resolveComponent`, then applies the workaround a module needs to
// disappear entirely rather than shrink to zero width. A plain
// `visible: item.visible` binding here deadlocks permanently the first time it
// goes false (see AGENT.md), so modules signal "hide me" through their own
// `contentVisible` property; modules with nothing to hide don't declare it,
// so this defaults to shown.
//
// `modelData` must be a `required property` — Qt's documented mechanism for a
// plain-array Repeater model. As soon as a delegate declares any required
// property Qt stops injecting the ambient modelData/index context properties,
// so a bare `modelData` here would silently resolve against an ancestor's
// instead (this bar's own screen, from shell.qml's Variants).
Loader {
    required property var resolveComponent
    required property string modelData

    sourceComponent: resolveComponent(modelData)
    // `active: false` alone would still reserve RowLayout spacing on both
    // sides; explicit `visible` excludes it properly.
    visible: item ? (item.contentVisible === undefined ? true : item.contentVisible) : false
    Layout.preferredWidth: (item as Item)?.implicitWidth ?? 0
}
