pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.shared

// Every `qs ipc call` target, and the state only they write. shell.qml
// instantiates this once and hands it what it needs from the shell.
Scope {
    id: ipc

    // Fallback output for a call that has none to report.
    required property var mainScreen
    // shell.qml's monitor-name -> Bar lookup, "ACTIVE" meaning the focused one.
    required property var barOn

    // Auto-hide overrides, name -> hidden, read by every Bar. Only IPC writes
    // them, so they live here; not on each bar, so an output's survives it
    // being unplugged. Workspaces are keyed by name because Hyprland hands a
    // named workspace a new id each time it's created.
    property var barOutputOverrides: ({})
    property var barWorkspaceOverrides: ({})

    // Backs `visibility` and `visibility_workspace`; scope is "output" or
    // "workspace". Returns what `qs ipc call` prints.
    function applyBarOverride(scope, action, monitorName) {
        const bar = ipc.barOn(monitorName);
        if (!bar)
            return ipc.barIpcError(`no bar on monitor "${monitorName}"`);
        const output = bar.modelData.name;
        const ws = bar.workspace;
        const perWorkspace = scope === "workspace";
        if (perWorkspace && !ws)
            return ipc.barIpcError(`no workspace on ${output}`);

        const key = perWorkspace ? ws.name : output;
        const overrides = Object.assign({}, perWorkspace ? ipc.barWorkspaceOverrides : ipc.barOutputOverrides);
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
            return ipc.barIpcError(`unknown action "${action}" — hide, unhide, toggle or auto`);
        }

        if (value === null)
            delete overrides[key];
        else
            overrides[key] = value;
        if (perWorkspace)
            ipc.barWorkspaceOverrides = overrides;
        else
            ipc.barOutputOverrides = overrides;
        bar.skipDelay();
        // Asking for hidden means now, not when a timed peek runs out. Only
        // an ask: `auto` or a masked `unhide` ending hidden leaves it be.
        if (value === true)
            bar.endTimedPeek();

        const state = bar.shouldHide ? "hidden" : "shown";
        const label = perWorkspace ? `workspace ${ws.name}` : output;
        const source = value === null ? "auto" : "forced";
        // An output override outranks a workspace one, so say when it's what
        // the screen is actually showing.
        const masked = (perWorkspace && bar.outputOverride !== null) ? ", output override wins" : "";
        OsdService.showMessage("󰍹", `Bar ${state} · ${label} · ${source}${masked}`, !bar.shouldHide, bar.modelData);
        return `${output}: ${state} (${label}: ${source}${masked})`;
    }

    // Capped at a day: Timer.interval is an int, and an overflowed one never
    // fires, leaving the peek up.
    function barPeek(seconds, monitorName) {
        if (!(seconds > 0 && seconds <= 86400))
            return ipc.barIpcError(`seconds must be in (0, 86400], got ${seconds}`);
        const bar = ipc.barOn(monitorName);
        if (!bar)
            return ipc.barIpcError(`no bar on monitor "${monitorName}"`);
        const output = bar.modelData.name;
        if (!bar.peekFor(Math.max(1, Math.round(seconds * 1000))))
            return `${output}: shown, nothing to peek`;
        return `${output}: peeking for ${seconds}s`;
    }

    // "+5", "-5" or "5" in points; NaN, with a warning, for anything else,
    // rather than flashing an OSD that didn't change.
    function osdDelta(delta) {
        const points = parseInt(delta);
        if (isNaN(points))
            console.warn(`osd ipc: delta must be an integer like +5 or -5, got "${delta}"`);
        return points;
    }

    function barIpcError(message) {
        console.warn("bar ipc: " + message);
        return "error: " + message;
    }

    // Drives the panel from a keybind, e.g.
    //   bind = SUPER, N, exec, qs ipc call notifications toggle
    // An IPC call has no widget to report a screen, so it targets the focused
    // output.
    IpcHandler {
        target: "notifications"

        function toggle(): void {
            NotificationService.toggleCenter(Screens.focused() || ipc.mainScreen);
        }

        function open(): void {
            if (!NotificationService.centerOpen)
                NotificationService.toggleCenter(Screens.focused() || ipc.mainScreen);
        }

        function close(): void {
            NotificationService.closeCenter();
        }

        function clear(): void {
            NotificationService.clearAll();
        }
    }

    // Auto-hide overrides and peek, e.g.
    //   bind = SUPER, B, exec, qs ipc call bar visibility toggle ACTIVE
    //   qs ipc call bar visibility_workspace hide DP-1
    // action: hide | unhide | toggle | auto; monitor: a name, or ACTIVE for the
    // focused one. `visibility` covers every workspace on that output;
    // `visibility_workspace` covers its current workspace, wherever that
    // workspace goes. The output's setting outranks the workspace's.
    // `peek` brings a hidden bar over the windows for that many seconds without
    // reserving space, like resting the cursor on the top edge:
    //   qs ipc call bar peek 3 ACTIVE
    IpcHandler {
        target: "bar"

        function visibility(action: string, monitor: string): string {
            return ipc.applyBarOverride("output", action, monitor);
        }

        function visibility_workspace(action: string, monitor: string): string {
            return ipc.applyBarOverride("workspace", action, monitor);
        }

        function peek(seconds: real, monitor: string): string {
            return ipc.barPeek(seconds, monitor);
        }
    }

    // The keybinds call in here, and this owns the change as well as the
    // display, e.g.
    //   bind  = , XF86AudioRaiseVolume, exec, qs ipc call osd volume +5
    //   bindn = , Caps_Lock,            exec, qs ipc call osd lock capslock
    // Lock keys only report — the compositor has already toggled them by the
    // time this runs, which is exactly why the bind must be non-consuming.
    IpcHandler {
        target: "osd"

        function volume(delta: string): void {
            const points = ipc.osdDelta(delta);
            if (!AudioService.ready || isNaN(points))
                return;
            AudioService.bumpPct(points);
            OsdService.show("volume");
        }

        function mute(): void {
            if (!AudioService.ready)
                return;
            AudioService.toggleMute();
            OsdService.show("volume");
        }

        // Silent on a machine with no backlight, rather than flashing an OSD
        // stuck at 0% — this config runs on outputs that have none.
        function brightness(delta: string): void {
            const points = ipc.osdDelta(delta);
            if (!BacklightService.available || isNaN(points))
                return;
            BacklightService.bumpPercent(points);
            OsdService.show("brightness");
        }

        // key: "capslock" | "numlock" | "scrolllock". Shown only once the
        // read has landed — the state is what the OSD is for, so a frame of
        // the previous one would be worse than the short settle wait.
        function lock(key: string): void {
            if (LockKeysService.keys.indexOf(key) === -1) {
                console.warn(`osd ipc: unknown lock key "${key}" — capslock, numlock or scrolllock`);
                return;
            }
            LockKeysService.refresh(key);
        }
    }

    Connections {
        target: LockKeysService
        function onRefreshed(key: string): void {
            OsdService.show(key);
        }
    }
}
