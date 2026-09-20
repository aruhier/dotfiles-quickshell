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
        model: Quickshell.screens

        // `bar.modelData`, never a bare `modelData`: unqualified, it resolves
        // against whatever ambient context is in scope instead of the
        // delegate's own property. `ComponentBehavior: Bound` makes that an
        // error rather than a silent wrong value.
        Bar {
            id: bar
            layout: root.layoutFor(bar.modelData.name)
        }
    }

    NotificationPopupWindow {
        screen: NotificationService.popupScreen || root.mainScreen
    }

    NotificationCenterPanel {
        screen: root.centerScreen
    }

    OsdWindow {
        screen: OsdService.screen || root.mainScreen
    }
}
