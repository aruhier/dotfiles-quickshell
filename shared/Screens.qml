pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Resolves a monitor name (from config, or from Hyprland) to the ShellScreen
// a window's `screen` property wants.
//
// This file is the compositor seam: `byName()` is generic, `focused()` and
// `scaleFor()` are the two functions a port to another compositor has to
// rewrite. Both degrade safely rather than breaking a layout — `focused()`
// returns null, which every call site already treats as "no opinion", and
// `scaleFor()` returns 1, which makes `snap()` the identity on whole numbers.
// A shell running unsnapped is exactly what this repo shipped before
// 2026-09-12: thin borders soften on a fractionally scaled output, nothing
// else. Text does not depend on any of this — see the MultiEffect rule in
// notes/text.md.
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

    // The output's real scale, which is not `ShellScreen.devicePixelRatio`:
    // that reports the integer `wl_output` scale Hyprland advertises for
    // legacy clients (2 on a 1.25 output), while the surface is rendered
    // through `wp_fractional_scale_v1` at the fractional value.
    //
    // Hyprland is asked because nothing else here knows. Quickshell's
    // ShellScreen carries name/model/serial, x/y/width/height,
    // physical/logicalPixelDensity, devicePixelRatio and orientation, and none
    // of them yield 1.25 — the two densities are Qt's DPI figures and their
    // ratio is 1.167, not the scale — and Qt exposes the fractional surface
    // scale to QML nowhere. 1 when the monitor is unknown, which only
    // under-corrects.
    function scaleFor(screen) {
        if (!screen)
            return 1;
        const monitor = Hyprland.monitorFor(screen);
        return monitor && monitor.scale > 0 ? monitor.scale : 1;
    }

    // Rounds a logical length so it lands on a whole device pixel. Anything
    // that offsets a whole subtree needs this: below an off-grid container
    // every glyph stem and 1px border renders blended across two physical
    // columns at half intensity. See notes/text.md.
    //
    // Per-scale and not a rounder constant on purpose — the multiple that
    // stays on the grid is the denominator of the scale (4 at 1.25, 3 at
    // 1.333, 5 at 1.6), so no single constant covers the outputs a config
    // might meet.
    function snap(length, screen) {
        const scale = scaleFor(screen);
        return Math.round(length * scale) / scale;
    }

    // Adjusts an inset so that what it places lands on a whole *logical*
    // pixel. Glyph origins are logical, so a text subtree carrying a fraction
    // renders every stem at its own subpixel offset however exact its device
    // position is — snap() fixes only the device half. See notes/text.md.
    //
    // Solved for the landing place rather than the inset, because whether a
    // subtree lands whole depends on where its container already is: an inset
    // that works under a panel on one output is off by a fraction under the
    // same panel on another. `edge` is where the inset starts, measured
    // rightwards, in the window's own coordinates; negate both for an inset
    // running the other way.
    //
    // A landing that is *also* a whole device pixel keeps the outline it
    // places crisp too, so one is preferred when the scale puts one within
    // 2px: that is every scale whose fractional part is halves, thirds,
    // quarters or fifths — 1.25 lands on fours, 1.5 on twos. Failing that the
    // nearest whole logical pixel wins, since text is the thing being placed.
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
