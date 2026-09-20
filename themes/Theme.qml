pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Palette, type and shared geometry for the bar. Singleton: static data
// shared process-wide rather than one instance per output.
//
// A value that only one file reads — a gesture's distances, a surface's own
// metrics, a spring's constants — lives in that file, not here.
QtObject {
    readonly property color barBg: "#2d2d2d"
    readonly property color text: "#A3A3AB"
    readonly property color textBright: "#E5D4CE"
    readonly property color accent: "#6AA099"

    readonly property color barBorder: accent
    readonly property color accentText: barBg

    readonly property color groupBg: "#424242"
    readonly property color groupText: textBright

    // The submap group's pill: cream, the empty-workspace cap colour, rather
    // than the accent — a teal pill next to the teal border stripe merged
    // into it. Pink/orange/red already mean urgent/recording/critical.
    readonly property color submapBg: textBright
    readonly property color submapText: workspaceEmptyText

    // Hover popup and tooltip chrome: darker than the bar, bordered with
    // `accent`, so a popup reads as a surface over it rather than part of it.
    readonly property color popupBg: "#1e1e1e"

    readonly property color workspaceBg: "#9BBFBA"
    readonly property color workspaceEmptyBg: textBright
    readonly property color workspaceEmptyText: "#252527"
    // Pink means urgent: a workspace, or the bell with notifications waiting.
    readonly property color urgent: "#F98BA4"
    readonly property color workspaceUrgent: urgent
    // A workspace active on its own monitor but not system-focused: between
    // workspaceBg and accent. See Workspaces.qml.
    readonly property color workspaceActiveBg: Qt.tint(workspaceBg, Qt.rgba(accent.r, accent.g, accent.b, 0.5))
    // A relative darken (Qt.darker() factor), not a flat color: every state
    // above stays distinguishable while hovered, and the dark label text
    // gains contrast rather than losing it.
    readonly property real workspaceHoverDarken: 1.15
    // Workspace hover preview: the "desktop" behind the thumbnails is lighter
    // than popupBg, so the preview reads as a screen inside the chrome.
    readonly property color workspacePreviewBg: barBg

    // Light enough to read as text on the group pill (4.4:1); a saturated
    // red only works as a background, landing at 2.7:1 here.
    readonly property color critical: "#FF8A80"
    readonly property color privacyActive: "#D14005"

    // One family, not a CSS fallback chain — QML's font.family takes a single
    // name and this Qt build's Text has no font.families. Nerd Font icon
    // codepoints come from Qt's automatic per-glyph fallback.
    readonly property string fontFamily: "Inter Variable"
    readonly property int fontSize: 12
    // Inter's wght axis, not a QFont weight — see StyledText.qml. Read by
    // StyledText and by any FontMetrics measuring the same face.
    readonly property int fontWeight: 450
    readonly property int fontWeightBold: 700
    // Nerd Font glyphs render smaller than Latin text at the same pixelSize,
    // so icons size off this instead. Tuned by eye.
    readonly property int iconFontSize: 15

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

    // Per-module bias on iconFontSize (1.0 = no change), for glyph sets that
    // read bigger/smaller than their neighbours.
    function iconSize(ratio) {
        return iconFontSize * (ratio === undefined ? 1.0 : ratio);
    }

    readonly property int barHeight: 22
    // Bottom border stripe: real extra height below the content area, not an
    // overlay.
    readonly property int barBorderHeight: 3

    // Between modules in a row.
    readonly property int moduleSpacing: 10
    // Between a module's icon and its label.
    readonly property int iconLabelSpacing: 6
    // Inner pad on a left/right group's center-facing side; the flush edge
    // gets none.
    readonly property int groupEdgePadding: 12
    // A flush-edge module's own outer margin.
    readonly property int moduleOuterMargin: 4
    // The center pill's caps.
    readonly property int centerCapWidth: 15

    // Stops a spring once this close to its target instead of approaching it
    // forever. Tuned for pixel-scale values; springs on a 0..1 scale need
    // their own much smaller epsilon (see PressSpring.qml).
    readonly property real springEpsilon: 0.25
}
