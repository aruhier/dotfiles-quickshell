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

    // Every applied override, for `output`'s bar to act on now. A signal, not
    // a watch on the maps: a repeated `hide` changes no value but must still
    // end a timed peek.
    signal overrideApplied(string output, bool forcedHidden)

    // Applies `action` (hide | unhide | toggle | auto) to `output`, or to the
    // workspace `workspaceName` when it isn't "". `current` is what that level
    // shows now, which only `toggle` reads. Returns the override now set —
    // true, false, or null for auto — or undefined for an unknown action,
    // which changes and emits nothing.
    function apply(output, workspaceName, action, current) {
        const perWorkspace = workspaceName !== "";
        const key = perWorkspace ? workspaceName : output;
        const overrides = Object.assign({}, perWorkspace ? root.workspaceOverrides : root.outputOverrides);
        // Toggle leaves auto by forcing the opposite of what this level shows
        // now, and any toggle while forced goes back to auto — even when auto
        // shows the same thing, so the press changes nothing visible.
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
        root.overrideApplied(output, value === true);
        return value;
    }
}
