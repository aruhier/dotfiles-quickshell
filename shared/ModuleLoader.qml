pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Repeater delegate for a single named bar module: resolves the module name
// to a Component via `resolveComponent`, then applies the visibility
// workaround a module needs to disappear entirely rather than just shrink
// to zero width. A plain `visible: item.visible` binding here would
// deadlock permanently the first time it goes false — see AGENT.md's
// Loader/visible note — so modules signal "hide me" via their own
// `contentVisible` property instead; modules with nothing to hide don't
// declare it, so this defaults to shown.
//
// `modelData` must be declared as a `required property` here (Qt's
// documented mechanism for a plain-array Repeater model), not read off the
// bare identifier: as soon as a delegate type declares *any* required
// property, Qt stops injecting the legacy ambient modelData/index context
// properties for it — so an unqualified `modelData` reference here would
// silently fall through to an unrelated ancestor's `modelData` (this bar's
// own screen, from shell.qml's Variants) instead of the Repeater's item.
// Cost real debugging time to track down.
Loader {
    id: moduleLoader

    required property var resolveComponent
    required property string modelData

    sourceComponent: resolveComponent(modelData)
    // `active: false` alone would still reserve RowLayout spacing on both
    // sides; explicit `visible` excludes it properly.
    visible: item ? (item.contentVisible === undefined ? true : item.contentVisible) : false
    Layout.preferredWidth: (item as Item)?.implicitWidth ?? 0
}
