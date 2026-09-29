pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Monitor names to ShellScreens, and the device pixel grid. The compositor
// seam: a port rewrites `focused()` and `scaleFor()`, and both degrade safely
// (null is "no opinion", 1 makes `snap()` the identity). See notes/style.md.
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

    // The real fractional scale, asked of Hyprland: `devicePixelRatio` is the
    // integer `wl_output` one (2 on a 1.25 output) and Qt exposes the
    // fractional one nowhere (notes/style.md). 1 when unknown, which only
    // under-corrects.
    function scaleFor(screen) {
        if (!screen)
            return 1;
        const monitor = Hyprland.monitorFor(screen);
        return monitor && monitor.scale > 0 ? monitor.scale : 1;
    }

    // Rounds a logical length onto a whole device pixel, for anything that
    // offsets a subtree: off the grid, stems and 1px borders blend across two
    // columns. Per-scale, as the multiple that stays on the grid depends on
    // the scale (4 at 1.25, 3 at 1.333). See notes/text.md.
    function snap(length, screen) {
        const scale = scaleFor(screen);
        return Math.round(length * scale) / scale;
    }

    // Adjusts an inset so text it places lands on a whole *logical* pixel,
    // which snap() doesn't give. Solved for the landing, since that depends on
    // where the container already is. `edge` is where the inset starts, in
    // window coordinates, rightwards. A landing within 2px that is also a
    // whole device pixel wins. See notes/text.md.
    function snapTextInset(inset, edge, screen) {
        const scale = scaleFor(screen);
        const nearest = Math.round(edge + inset);
        for (let offset = 0; offset <= 2; offset++) {
            for (const landing of [nearest + offset, nearest - offset]) {
                if (Math.abs(landing * scale - Math.round(landing * scale)) < 1e-3)
                    return landing - edge;
            }
        }
        return nearest - edge;
    }
}
