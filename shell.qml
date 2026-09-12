//@ pragma UseQApplication
//@ pragma AppId dev.aruhier.quickshell-bar
// Qt's default animation driver paces every GUI-thread animation (so every
// FrameSpring) off the refresh rate of the QScreen it thinks the window is on —
// always Qt's primary one for layer-shell windows — and then caps them at ~60Hz
// process-wide. The simple driver has neither the guess nor the cap. Takes
// effect at process start only, not on reload. See AGENTS.md for the measurements.
//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1
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

    // Which modules appear where, per output. Screens named in `mainScreens`
    // (check names with `hyprctl monitors -j`) get `mainLayout`, every other
    // screen gets `defaultLayout`. Module names must match a key in Bar.qml's
    // `moduleComponents`.
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

    // Fallback screen for the shared, single-instance windows below (toast
    // stack, control-center panel) before they have a real output to target.
    readonly property var mainScreen: Screens.byName(root.mainScreens[0])

    // The control-center panel is a single shared surface, but it's clicked
    // open from a per-output indicator, so it should appear on whichever
    // screen was clicked. NotificationService.centerScreen tracks that; fall
    // back to the main screen before the first-ever click.
    readonly property var centerScreen: NotificationService.centerScreen || root.mainScreen

    // Lets a Hyprland keybind drive the notification panel the same way the
    // bar indicator's click does, e.g.:
    //   bind = SUPER, N, exec, qs ipc call notifications toggle
    //
    // An IPC call has no widget of its own to report a screen, so these target
    // the focused output instead.
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

        // `bar.modelData`, not a bare `modelData`: an unqualified model
        // reference in a Variants delegate silently resolves against whatever
        // ambient context is in scope rather than the delegate's own property
        // (see AGENT.md — it cost real debugging time in ModuleLoader). The id
        // makes it unambiguous, and `pragma ComponentBehavior: Bound` turns
        // the ambiguous form into a compile error.
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
