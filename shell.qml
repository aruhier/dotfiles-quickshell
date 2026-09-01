//@ pragma UseQApplication
import Quickshell
import "modules"

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
        right: ["tray", "backlight", "volume", "privacy", "swaync", "weather", "clock"]
    })

    readonly property var defaultLayout: ({
        left: ["mpd", "submap"],
        center: ["workspaces"],
        right: ["backlight", "volume", "swaync", "clock"]
    })

    function layoutFor(screenName) {
        return root.mainScreens.indexOf(screenName) !== -1 ? root.mainLayout : root.defaultLayout;
    }

    Variants {
        model: Quickshell.screens

        Bar {
            layout: root.layoutFor(modelData.name)
        }
    }
}
