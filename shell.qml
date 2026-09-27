//@ pragma UseQApplication
//@ pragma AppId dev.aruhier.quickshell-bar
// Qt's default animation driver paces every GUI-thread animation off the
// refresh rate of the screen it thinks the window is on (always the primary
// one, for layer-shell) and caps it near 60Hz. The simple driver has neither.
// Takes effect at process start only, not on reload. Measurements: notes/rendering.md.
//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1
// Vulkan RHI instead of the default OpenGL: ~170MB RSS against ~257MB here,
// since the GL backend's per-window cost scales badly. Nothing else changes.
// See notes/rendering.md.
//@ pragma Env QSG_RHI_BACKEND=vulkan
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules
import qs.services
import qs.shared
import qs.shared.notifications
import qs.shared.osd
import qs.themes

// One Bar per output, with the per-monitor module layout configured below.
ShellRoot {
    id: root

    // Which modules appear where, per output. Screens in `mainScreens` (names
    // from `hyprctl monitors -j`) get `mainLayout`, the rest `defaultLayout`.
    // `left` and `right` are lists of module groups, ordered from the screen
    // edge inward; adjacent groups are drawn attached, as one pill, and a
    // group with nothing to show is left out. A group is
    // `{modules, color?, textColor?}`; both colours default to the shared
    // group palette. `center` is a plain module list. Module names must match
    // a key in Bar.qml's `moduleComponents`.
    readonly property var mainScreens: ["DP-1", "eDP-1"]

    readonly property var mainLayout: ({
        left: [
            { modules: ["mpd"] },
            // The submap is a mode the bar has entered, so it gets its own
            // colour rather than sitting inside the mpd group as a chip.
            { modules: ["submap"], color: Theme.submapBg, textColor: Theme.submapText }
        ],
        center: ["workspaces"],
        right: [{ modules: ["tray", "backlight", "battery", "volume", "privacy", "notifications", "weather", "clock"] }]
    })

    readonly property var defaultLayout: ({
        left: [
            { modules: ["mpd"] },
            { modules: ["submap"], color: Theme.submapBg, textColor: Theme.submapText }
        ],
        center: ["workspaces"],
        right: [{ modules: ["backlight", "battery", "volume", "notifications", "clock"] }]
    })

    function layoutFor(screenName) {
        return root.mainScreens.indexOf(screenName) !== -1 ? root.mainLayout : root.defaultLayout;
    }

    // Workspaces the bar hides on, to spare an OLED. "*" applies to every
    // output, a monitor name to that one only, and the two add up. A number
    // is a workspace id, a string its name — they differ here (id 1 is "a").
    // Arriving on one, the bar waits `barHideDelay` ms before it goes, so a
    // workspace passed through doesn't resize every window twice. See
    // notes/autohide.md.
    readonly property var barHideOn: ({
        "*": [1]
    })
    readonly property int barHideDelay: 1000

    // Set over IPC: name -> hidden. Kept here rather than on each bar so an
    // output's survives it being unplugged. Workspaces are keyed by name
    // because Hyprland hands a named workspace a new id each time it's created.
    property var barOutputOverrides: ({})
    property var barWorkspaceOverrides: ({})

    // "ACTIVE" is the focused output.
    function barOn(monitorName) {
        const name = monitorName === "ACTIVE" ? Screens.focused()?.name : monitorName;
        const bars = barVariants.instances;
        for (let i = 0; i < bars.length; i++) {
            if (bars[i].modelData.name === name)
                return bars[i];
        }
        return null;
    }

    // Backs both `bar` IPC calls; scope is "output" or "workspace". Returns
    // what `qs ipc call` prints.
    function applyBarOverride(scope, action, monitorName) {
        const bar = root.barOn(monitorName);
        if (!bar)
            return root.barIpcError(`no bar on monitor "${monitorName}"`);
        const output = bar.modelData.name;
        const ws = bar.workspace;
        const perWorkspace = scope === "workspace";
        if (perWorkspace && !ws)
            return root.barIpcError(`no workspace on ${output}`);

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
        case "show":
            value = false;
            break;
        case "auto":
            value = null;
            break;
        case "toggle":
            value = (!current === fallback) ? null : !current;
            break;
        default:
            return root.barIpcError(`unknown action "${action}" — hide, show, toggle or auto`);
        }

        const key = perWorkspace ? ws.name : output;
        const overrides = Object.assign({}, perWorkspace ? root.barWorkspaceOverrides : root.barOutputOverrides);
        if (value === null)
            delete overrides[key];
        else
            overrides[key] = value;
        if (perWorkspace)
            root.barWorkspaceOverrides = overrides;
        else
            root.barOutputOverrides = overrides;
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

    // Fallback for the shared windows below, before they have a real output;
    // any output at all on a machine with none of the named ones.
    readonly property var mainScreen: Screens.byName(root.mainScreens[0]) ?? Quickshell.screens[0] ?? null

    // One shared panel, opened from a per-output indicator, so it follows the
    // clicked screen — until the first-ever click, when there is none.
    readonly property var centerScreen: NotificationService.centerScreen || root.mainScreen

    // Drives the panel from a keybind, e.g.
    //   bind = SUPER, N, exec, qs ipc call notifications toggle
    // An IPC call has no widget to report a screen, so it targets the focused
    // output.
    IpcHandler {
        target: "notifications"

        function toggle(): void {
            NotificationService.toggleCenter(Screens.focused() || root.mainScreen);
        }

        function open(): void {
            if (!NotificationService.centerOpen)
                NotificationService.toggleCenter(Screens.focused() || root.mainScreen);
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
    // action: hide | show | toggle | auto; monitor: a name, or ACTIVE for the
    // focused one. `visibility` covers every workspace on that output;
    // `visibility_workspace` covers its current workspace, wherever that
    // workspace goes. The output's setting outranks the workspace's.
    IpcHandler {
        target: "bar"

        function visibility(action: string, monitor: string): string {
            return root.applyBarOverride("output", action, monitor);
        }

        function visibility_workspace(action: string, monitor: string): string {
            return root.applyBarOverride("workspace", action, monitor);
        }
    }

    // Moving a workspace to another output makes Hyprland switch the old
    // output to a new one, but Quickshell credits that switch to the focused
    // output, leaving a bar on a workspace it no longer shows.
    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            // v1 and v2 both fire per move; one refresh is enough.
            if (event.name === "moveworkspacev2")
                Hyprland.refreshMonitors();
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

    Variants {
        id: barVariants
        model: Quickshell.screens

        // `bar.modelData`, never a bare `modelData`: unqualified, it resolves
        // against whatever ambient context is in scope instead of the
        // delegate's own property. `ComponentBehavior: Bound` makes that an
        // error rather than a silent wrong value.
        Bar {
            id: bar
            layout: root.layoutFor(bar.modelData.name)
            hideOn: root.barHideOn
            hideDelay: root.barHideDelay
            outputOverrides: root.barOutputOverrides
            workspaceOverrides: root.barWorkspaceOverrides
        }
    }

    NotificationPopupWindow {
        id: toasts
        screen: NotificationService.popupScreen || root.mainScreen
        barReservesSpace: root.barOn(toasts.screen?.name)?.reservesSpace ?? true
    }

    NotificationCenterPanel {
        screen: root.centerScreen
    }

    OsdWindow {
        screen: OsdService.screen || root.mainScreen
    }
}
