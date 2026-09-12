pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Resolves a monitor name (from config, or from Hyprland) to the ShellScreen
// a window's `screen` property wants.
QtObject {
    function byName(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return null;
    }

    // null if Hyprland reports a monitor this shell doesn't know about.
    function focused() {
        const monitor = Hyprland.focusedMonitor;
        return monitor ? byName(monitor.name) : null;
    }
}
