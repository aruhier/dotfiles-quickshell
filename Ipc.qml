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

    // Backs both `bar` IPC calls; scope is "output" or "workspace". Returns
    // what `qs ipc call` prints.
    function applyBarOverride(scope, action, monitorName) {
        const bar = ipc.barOn(monitorName);
        if (!bar)
            return ipc.barIpcError(`no bar on monitor "${monitorName}"`);
        const output = bar.modelData.name;
        const ws = bar.workspace;
        const perWorkspace = scope === "workspace";
        if (perWorkspace && !ws)
            return ipc.barIpcError(`no workspace on ${output}`);

        // What this level shows now, and what it falls back to without an
        // override. A toggle landing on the fallback clears the override
        // instead of setting one, so two toggles always return to auto.
        const current = perWorkspace ? bar.hiddenForWorkspace : bar.shouldHide;
        const fallback = perWorkspace ? bar.hiddenByRule : bar.hiddenForWorkspace;
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
            value = (!current === fallback) ? null : !current;
            break;
        default:
            return ipc.barIpcError(`unknown action "${action}" — hide, unhide, toggle or auto`);
        }

        const key = perWorkspace ? ws.name : output;
        const overrides = Object.assign({}, perWorkspace ? ipc.barWorkspaceOverrides : ipc.barOutputOverrides);
        if (value === null)
            delete overrides[key];
        else
            overrides[key] = value;
        if (perWorkspace)
            ipc.barWorkspaceOverrides = overrides;
        else
            ipc.barOutputOverrides = overrides;
        bar.skipDelay();

        const state = bar.shouldHide ? "hidden" : "shown";
        const label = perWorkspace ? `workspace ${ws.name}` : output;
        const source = value === null ? "auto" : "forced";
        // An output override outranks a workspace one, so say when it's what
        // the screen is actually showing.
        const masked = (perWorkspace && bar.outputOverride !== null) ? ", output override wins" : "";
        OsdService.showMessage("󰍹", `Bar ${state} · ${label} · ${source}${masked}`, !bar.shouldHide, bar.modelData);
        return `${output}: ${state} (${label}: ${source}${masked})`;
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

    // Auto-hide overrides, e.g.
    //   bind = SUPER, B, exec, qs ipc call bar visibility toggle ACTIVE
    //   qs ipc call bar visibility_workspace hide DP-1
    // action: hide | unhide | toggle | auto; monitor: a name, or ACTIVE for the
    // focused one. `visibility` covers every workspace on that output;
    // `visibility_workspace` covers its current workspace, wherever that
    // workspace goes. The output's setting outranks the workspace's.
    IpcHandler {
        target: "bar"

        function visibility(action: string, monitor: string): string {
            return ipc.applyBarOverride("output", action, monitor);
        }

        function visibility_workspace(action: string, monitor: string): string {
            return ipc.applyBarOverride("workspace", action, monitor);
        }
    }

    // Replaces swayosd: the keybinds call in here instead of swayosd-client,
    // and this owns the change as well as the display, e.g.
    //   bind  = , XF86AudioRaiseVolume, exec, qs ipc call osd volume +5
    //   bindn = , Caps_Lock,            exec, qs ipc call osd lock capslock
    // Lock keys only report — the compositor has already toggled them by the
    // time this runs, which is exactly why the bind must be non-consuming.
    IpcHandler {
        target: "osd"

        function volume(delta: string): void {
            if (!AudioService.ready)
                return;
            AudioService.bumpPct(parseInt(delta) || 0);
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
            if (!BacklightService.available)
                return;
            BacklightService.bumpPercent(parseInt(delta) || 0);
            OsdService.show("brightness");
        }

        // key: "capslock" | "numlock" | "scrolllock". Shown only once the
        // read has landed — the state is what the OSD is for, so a frame of
        // the previous one would be worse than the millisecond's wait.
        function lock(key: string): void {
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
