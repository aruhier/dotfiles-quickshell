pragma ComponentBehavior: Bound
import QtQuick
import qs.themes

// Repeater delegate for one named bar module: resolves the name via
// `resolveComponent` and hides a module that sets `contentVisible` false —
// not `item.visible`, which deadlocks (notes/qml-gotchas.md).
//
// `modelData` must be `required`: without it Qt injects an ambient context
// property instead, and a bare `modelData` would resolve against an ancestor's
// (this bar's own screen, from shell.qml's Variants).
Loader {
    id: loader

    required property var resolveComponent
    required property string modelData
    // Set by a collapsing ModuleGroup so the module stays drawn while the
    // group's width shrinks over it, rather than vanishing a frame ahead.
    property bool keepShown: false
    // The group's text colour, handed to a module that declares `textColor`
    // (BarModule). Workspaces and Privacy colour themselves.
    property color textColor: Theme.groupText

    readonly property bool hasContent: item ? (item.contentVisible === undefined ? true : item.contentVisible) : false

    sourceComponent: resolveComponent(modelData)
    // `active: false` alone still reserves RowLayout spacing on both sides.
    visible: hasContent || keepShown

    Binding {
        target: loader.item
        property: "textColor"
        value: loader.textColor
        when: loader.item?.textColor !== undefined
    }
}
