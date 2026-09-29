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
import qs
import qs.modules
import qs.services
import qs.shared
import qs.shared.notificationpanel
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
        "*": [1, 10]
    })
    readonly property int barHideDelay: 600

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

    // Fallback for the shared windows below, before they have a real output;
    // any output at all on a machine with none of the named ones.
    readonly property var mainScreen: Screens.byName(root.mainScreens[0]) ?? Quickshell.screens[0] ?? null

    // One shared panel, opened from a per-output indicator, so it follows the
    // clicked screen — until the first-ever click, when there is none.
    readonly property var centerScreen: NotificationService.centerScreen || root.mainScreen

    // Moving a workspace to another output makes Hyprland switch the old
    // output to a new one, but Quickshell credits that switch to the focused
    // output, leaving a bar on a workspace it no longer shows.
    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            // v1 and v2 both fire per move; one refresh is enough.
            if (event.name === "moveworkspacev2")
                HyprlandRefreshService.monitors();
            else if (root.toplevelEvents.includes(event.name))
                HyprlandRefreshService.toplevels();
        }
    }
    // What the bar's auto-hide counts (floating, hidden, grouped) is only in
    // lastIpcObject, which no event updates.
    readonly property var toplevelEvents: ["openwindow", "closewindow", "changefloatingmode", "togglegroup", "moveintogroup", "moveoutofgroup"]

    // All IPC: see Ipc.qml.
    Ipc {
        id: ipc
        mainScreen: root.mainScreen
        barOn: root.barOn
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
        targetScreen: OsdService.screen || root.mainScreen
    }
}
