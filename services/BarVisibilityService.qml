pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// The bar's auto-hide overrides, name -> hidden, read by every Bar and set by
// the `bar` IPC target. A singleton, not state on each Bar, so an output's
// override survives it being unplugged. Workspaces are keyed by name because
// Hyprland hands a named workspace a new id each time it's created. In
// memory: a reload drops them. See notes/autohide.md.
QtObject {
    id: root

    property var outputOverrides: ({})
    property var workspaceOverrides: ({})

    // Applies `action` (hide | unhide | toggle | auto) to `bar`'s output, or
    // to its current workspace when `perWorkspace`. Returns the override now
    // set — true, false, or null for auto — or undefined for an unknown
    // action, changing nothing.
    function apply(bar, perWorkspace, action) {
        const key = perWorkspace ? bar.workspace.name : bar.modelData.name;
        const overrides = Object.assign({}, perWorkspace ? root.workspaceOverrides : root.outputOverrides);
        // Toggle leaves auto by forcing the opposite of what this level shows
        // now, and any toggle while forced goes back to auto — even when auto
        // shows the same thing, so the press changes nothing visible.
        const current = perWorkspace ? bar.hiddenForWorkspace : bar.shouldHide;
        let value;
        switch (action) {
        case "hide":
            value = true;
            break;
        case "unhide":
            value = false;
            break;
        case "auto":
            value = null;
            break;
        case "toggle":
            value = (key in overrides) ? null : !current;
            break;
        default:
            return undefined;
        }

        if (value === null)
            delete overrides[key];
        else
            overrides[key] = value;
        if (perWorkspace)
            root.workspaceOverrides = overrides;
        else
            root.outputOverrides = overrides;
        // Asked for, so now: no hide delay.
        bar.skipDelay();
        // Asking for hidden means now, not when a timed peek runs out. Only
        // an ask: `auto` or a masked `unhide` ending hidden leaves it be.
        if (value === true)
            bar.endTimedPeek();
        return value;
    }
}
