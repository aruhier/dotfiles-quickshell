//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules"
import "services"
import "shared/notifications"

// One Bar per output, with per-monitor module layout configured below.
ShellRoot {
    id: root

    // Which modules appear where, per output. Screens named in
    // `mainScreens` (check names with `hyprctl monitors -j`) get
    // `mainLayout`; every other screen gets `defaultLayout`. Module names
    // must match a key in Bar.qml's `moduleComponents`.
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

    function screenByName(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return null;
    }

    // Resolved ShellScreen for mainScreens[0] — fallback for the shared,
    // single-instance UI surfaces below (toast stack, control-center panel)
    // before they have a real screen to target of their own, same
    // convention Tray/Privacy/Weather already follow for the one shared
    // "expensive" surface of their subsystem.
    readonly property var mainScreen: root.screenByName(root.mainScreens[0])

    // The control-center panel is likewise a single shared surface, but
    // (unlike the toast stack) it's click-triggered from a per-output
    // indicator — it should open on whichever screen was actually clicked,
    // not always the main screen. NotificationService.centerScreen tracks
    // that (set from the clicked bar's own `screen`, not looked up by
    // name); fall back to the main screen before the first-ever click,
    // when it's still null.
    readonly property var centerScreen: NotificationService.centerScreen || root.mainScreen

    // Resolved ShellScreen for whichever output Hyprland currently has
    // focused — what the IPC handler below targets, since (unlike a bar
    // indicator's click) an IPC call has no widget/screen of its own to
    // report. Falls back to the main screen if Hyprland reports a monitor
    // name this shell doesn't know about.
    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        return (monitor && root.screenByName(monitor.name)) || root.mainScreen;
    }

    // Lets a Hyprland keybind drive the notification panel the same way the
    // bar indicator's click does (NotificationCenter.qml), e.g.:
    //   bind = SUPER, N, exec, qs ipc call notifications toggle
    IpcHandler {
        target: "notifications"

        function toggle(): void {
            NotificationService.toggleCenter(root.focusedScreen());
        }

        function open(): void {
            if (!NotificationService.centerOpen)
                NotificationService.toggleCenter(root.focusedScreen());
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

        Bar {
            layout: root.layoutFor(modelData.name)
        }
    }

    NotificationPopupWindow {
        screen: NotificationService.popupScreen || root.mainScreen
    }

    NotificationCenterPanel {
        screen: root.centerScreen
    }
}
