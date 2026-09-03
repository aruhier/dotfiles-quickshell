//@ pragma UseQApplication
import Quickshell
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
    readonly property var mainScreens: ["DP-1"]

    readonly property var mainLayout: ({
        left: ["mpd", "submap"],
        center: ["workspaces"],
        right: ["tray", "backlight", "volume", "privacy", "notifications", "weather", "clock"]
    })

    readonly property var defaultLayout: ({
        left: ["mpd", "submap"],
        center: ["workspaces"],
        right: ["backlight", "volume", "notifications", "clock"]
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

    // Resolved ShellScreen for mainScreens[0] — the notification popup
    // stack is a single, shared UI surface (not one per output, unlike the
    // bar itself), so it lives on the main screen only, same convention
    // Tray/Privacy/Weather already follow for the one shared "expensive"
    // surface of their subsystem.
    readonly property var mainScreen: root.screenByName(root.mainScreens[0])

    // The control-center panel is likewise a single shared surface, but
    // (unlike the toast stack) it's click-triggered from a per-output
    // indicator — it should open on whichever screen was actually clicked,
    // not always the main screen. NotificationService.centerScreen tracks
    // that (set from the clicked bar's own `screen`, not looked up by
    // name); fall back to the main screen before the first-ever click,
    // when it's still null.
    readonly property var centerScreen: NotificationService.centerScreen || root.mainScreen

    Variants {
        model: Quickshell.screens

        Bar {
            layout: root.layoutFor(modelData.name)
        }
    }

    NotificationPopupWindow {
        screen: root.mainScreen
    }

    NotificationCenterPanel {
        screen: root.centerScreen
    }
}
