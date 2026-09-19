pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.themes

// A row of named bar modules: one ModuleLoader per entry of `model`, plus
// what a container needs to know about them — whether any has something to
// show — and the `keepShown` hold a collapsing ModuleGroup puts on them. Used
// bare for the bar's floating center, inside a pill by ModuleGroup.
RowLayout {
    id: row

    property alias model: repeater.model
    required property var resolveComponent
    // Handed to every module — see BarModule.
    property color textColor: Theme.groupText
    // Handed to every loader — see ModuleLoader.
    property bool keepShown: false

    // Whether any module has something to show. Read off the modules' own
    // `contentVisible` (recounted on change) rather than this row's width:
    // the width holds while a group collapses over it, since the loaders stay
    // shown, so it can't be the thing that decides when the collapse starts.
    property bool hasContent: false

    function recount() {
        let any = false;
        for (let i = 0; i < repeater.count; i++) {
            const loader = repeater.itemAt(i) as ModuleLoader;
            if (loader && loader.hasContent)
                any = true;
        }
        hasContent = any;
    }

    spacing: Theme.moduleSpacing

    Repeater {
        id: repeater
        delegate: ModuleLoader {
            resolveComponent: row.resolveComponent
            textColor: row.textColor
            keepShown: row.keepShown
            onHasContentChanged: row.recount()
        }
        onItemAdded: row.recount()
        onItemRemoved: row.recount()
    }
}
