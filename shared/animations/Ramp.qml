pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Stage maths for staged animations. Pure functions, so a binding calling one
// depends only on its arguments.
QtObject {
    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    // 0..1 progress of `v` across [from, to], clamped at both ends: the shape
    // every staged animation here reads its stage off, from a plate's opening
    // to the reveal ramps riding it. A zero-width range is "not there yet"
    // below `to` rather than a division by zero.
    function ramp(v, from, to) {
        const span = to - from;
        return span === 0 ? (v >= to ? 1 : 0) : clamp01((v - from) / span);
    }

    // Content opacity over a plate's 0..1 opening: in over its second half,
    // so nothing draws through widths or heights it has no room in. The OSD
    // pill and the hover popups share it; a toast reveals later (0.72), see
    // NotificationCard.qml.
    function reveal(opened) {
        return ramp(opened, 0.45, 0.80);
    }
}
