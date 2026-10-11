pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.shared

// Finds text whose glyphs start off a whole logical px, which blurs letters
// at fractional scales (notes/text.md). At scale 1 Qt rounds the origin, so
// those outputs are skipped. Off unless the shell starts with
// QS_DEBUG_TEXTGRID set; then every StyledText registers here and
// `qs ipc call debug textGrid` reports. Run it at rest, on each scale in use.
QtObject {
    id: root

    // Read once: the environment is the process's, so a hot reload doesn't
    // change it, and text built before it was set would be missed anyway.
    readonly property bool enabled: !!Quickshell.env("QS_DEBUG_TEXTGRID")

    property var items: []

    function track(item) {
        root.items.push(item);
    }

    function untrack(item) {
        const i = root.items.indexOf(item);
        if (i !== -1)
            root.items.splice(i, 1);
    }

    // Where the first line's glyphs start, in the window's logical px. A
    // centred or right-aligned single line starts inside the item, by however
    // much space it leaves; wrapped lines each start differently, so only the
    // item's own x is checked for those.
    function glyphX(item) {
        let x = item.mapToItem(null, 0, 0).x;
        if (item.lineCount !== 1)
            return x;
        const free = item.width - item.contentWidth;
        if (item.effectiveHorizontalAlignment === Text.AlignHCenter)
            x += free / 2;
        else if (item.effectiveHorizontalAlignment === Text.AlignRight)
            x += free;
        return x;
    }

    // The nearest enclosing file's type name, e.g. "NotificationCard".
    function owner(item) {
        for (let it = item.parent; it; it = it.parent) {
            const name = String(it).match(/^(\w+?)_QMLTYPE_/);
            if (name && name[1] !== "StyledText")
                return name[1];
        }
        return "?";
    }

    // One line per offender: screen, owning file, x, and the start of the text.
    function report() {
        const lines = [];
        let checked = 0;
        for (const item of root.items) {
            const win = item.Window.window;
            if (!win || !win.visible || !item.visible || item.text === "")
                continue;
            const screen = Screens.byName(item.Screen.name);
            if (Screens.scaleFor(screen) === 1)
                continue;
            checked++;
            const x = root.glyphX(item);
            if (Math.abs(x - Math.round(x)) > 1e-3)
                lines.push(`${item.Screen.name} ${root.owner(item)} x=${x.toFixed(2)}: ${item.text.slice(0, 40).replace(/\n/g, " ")}`);
        }
        lines.unshift(`${lines.length} of ${checked} visible texts off the grid`);
        return lines.join("\n");
    }
}
