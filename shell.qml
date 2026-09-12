//@ pragma UseQApplication
//@ pragma AppId dev.aruhier.quickshell-bar
// Qt's default animation driver paces every GUI-thread animation off the
// refresh rate of the screen it thinks the window is on (always the primary
// one, for layer-shell) and caps it near 60Hz. The simple driver has neither.
// Takes effect at process start only, not on reload. Measurements: AGENTS.md.
//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1
// Vulkan RHI instead of the default OpenGL: ~170MB RSS against ~257MB here,
// since the GL backend's per-window cost scales badly. Nothing else changes.
// See AGENTS.md.
//@ pragma Env QSG_RHI_BACKEND=vulkan
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import qs.modules
import qs.services
import qs.shared
import qs.shared.notifications

// One Bar per output, with the per-monitor module layout configured below.
ShellRoot {
    id: root

    // Which modules appear where, per output. Screens in `mainScreens` (names
    // from `hyprctl monitors -j`) get `mainLayout`, the rest `defaultLayout`.
    // Module names must match a key in Bar.qml's `moduleComponents`.
    readonly property var mainScreens: ["DP-1", "eDP-1"]

    readonly property var mainLayout: ({
        left: ["mpd", "submap"],
        center: ["workspaces"],
        right: ["tray", "backlight", "battery", "volume", "privacy", "notifications", "weather", "clock"]
    })

    readonly property var defaultLayout: ({
        left: ["mpd", "submap"],
        center: ["workspaces"],
        right: ["backlight", "battery", "volume", "notifications", "clock"]
    })

    function layoutFor(screenName) {
        return root.mainScreens.indexOf(screenName) !== -1 ? root.mainLayout : root.defaultLayout;
    }

    // Fallback for the shared windows below, before they have a real output.
    readonly property var mainScreen: Screens.byName(root.mainScreens[0])

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
}
