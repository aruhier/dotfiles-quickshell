pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Screen lookups shared by shell.qml and NotificationService.qml, both of
// which have to resolve a monitor *name* (from config, or from Hyprland) to
// the ShellScreen that a window's `screen` property wants.
QtObject {
    function byName(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return null;
    }

    // The output Hyprland currently has focused, or null if it reports a
    // monitor this shell doesn't know about.
    function focused() {
        const monitor = Hyprland.focusedMonitor;
        return monitor ? byName(monitor.name) : null;
    }
}
