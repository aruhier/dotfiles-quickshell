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

    // Hyprland's monitor for `screen`, looked up in `Hyprland.monitors` so a
    // binding re-runs when the list changes. `Hyprland.monitorFor()` is a
    // one-shot call: after an output drops out and returns, a binding on it
    // keeps a deleted monitor or null (notes/quickshell-quirks.md).
    function monitorFor(screen) {
        if (!screen)
            return null;
        return Hyprland.monitors.values.find(m => m.name === screen.name) ?? null;
    }

    // The real fractional scale, asked of Hyprland: `devicePixelRatio` is the
    // integer `wl_output` one (2 on a 1.25 output) and Qt exposes the
    // fractional one nowhere (notes/style.md). 1 when unknown, which only
    // under-corrects.
    function scaleFor(screen) {
        if (!screen)
            return 1;
        const monitor = monitorFor(screen);
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

    // Rounds a surface's size up to whole logical px that are also whole
    // device px (a multiple of 4 at 1.25): the compositor otherwise resamples
    // the buffer, and the edge row lands on a partial pixel. The search covers
    // every scale Hyprland suggests; past it, plain ceil.
    function snapSurface(length, screen) {
        const scale = scaleFor(screen);
        // Float noise must not cost a whole pixel (378.0000001 -> 379).
        const base = Math.ceil(length - 1e-6);
        for (let size = base; size < base + 16; size++) {
            if (onGrid(size, scale))
                return size;
        }
        return base;
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
                if (onGrid(landing, scale))
                    return landing - edge;
            }
        }
        return nearest - edge;
    }

    // Whether a logical length is a whole number of device px. Tolerant, as
    // Hyprland's scale is a float (4/3 isn't exact).
    function onGrid(length, scale) {
        return Math.abs(length * scale - Math.round(length * scale)) < 1e-3;
    }
}
