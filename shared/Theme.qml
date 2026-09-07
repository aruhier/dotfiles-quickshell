pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Palette + metrics for the whole bar. Singleton: static data shared
// process-wide rather than one instance per output.
QtObject {
    readonly property color barBg: "#2d2d2d"
    readonly property color barBorder: "#6AA099"
    readonly property color text: "#A3A3AB"
    readonly property color textBright: "#E5D4CE"

    readonly property color groupBg: "#424242"
    readonly property color groupText: "#E5D4CE"

    readonly property color accent: "#6AA099"
    readonly property color accentText: "#2d2d2d"

    // Hover popup and tooltip chrome: darker than the bar, bordered with
    // `accent`, so a popup reads as a surface over it rather than part of it.
    readonly property color popupBg: "#1e1e1e"

    readonly property color workspaceBg: "#9BBFBA"
    readonly property color workspaceEmptyBg: "#E5D4CE"
    readonly property color workspaceEmptyText: "#252527"
    readonly property color workspaceUrgent: "#F98BA4"
    // A workspace active on its own monitor but not system-focused: between
    // workspaceBg and accent. See Workspaces.qml.
    readonly property color workspaceActiveBg: Qt.tint(workspaceBg, Qt.rgba(accent.r, accent.g, accent.b, 0.5))

    // Lightened from waybar's #f53c3c, which it only ever used as a
    // background: as text on groupBg that lands at 2.7:1. This reads red at
    // 4.4:1 on the group pill.
    readonly property color critical: "#FF8A80"
    readonly property color privacyActive: "#D14005"

    // One family, not a CSS fallback chain — QML's font.family takes a single
    // name and this Qt build's Text has no font.families. Nerd Font icon
    // codepoints come from Qt's automatic per-glyph fallback.
    readonly property string fontFamily: "Inter Variable"
    readonly property int fontSize: 12
    // Nerd Font glyphs render smaller than Latin text at the same pixelSize,
    // so icons size off this instead. Tuned by eye.
    readonly property int iconFontSize: 15

    // Per-module bias on iconFontSize (1.0 = no change), for glyph sets that
    // read bigger/smaller than their neighbours.
    function iconSize(ratio) {
        return iconFontSize * (ratio === undefined ? 1.0 : ratio);
    }

    readonly property int barHeight: 22
    // Bottom border stripe: real extra height below the content area, not an
    // overlay.
    readonly property int barBorderHeight: 3

    // Inner pad on a left/right group's center-facing side; the flush edge
    // gets none.
    readonly property int groupEdgePadding: 12
    // A flush-edge module's own outer margin.
    readonly property int moduleOuterMargin: 4
    // The center pill's caps.
    readonly property int centerCapWidth: 15

    // Spring constants for shared/animations/FrameSpring.qml, which
    // integrates the mass-spring-damper ODE directly — so Hyprland's own
    // physical constants are the right values here.
    readonly property real frameSpringStiffness: 460
    readonly property real frameSpringDamping: 35
    readonly property real frameSpringMass: 0.6
    // Stops a spring once this close to its target instead of approaching it
    // forever. Tuned for pixel-scale values; springs on a 0..1 scale need
    // their own much smaller epsilon (see PressSpring.qml).
    readonly property real springEpsilon: 0.25

    // Faster variant for Workspaces.qml, whose pill/delegate/indicator widths
    // all move together: same damping ratio (ζ ≈ 1.05), roughly 2x the
    // natural frequency. More damping than this made the motion read *worse*,
    // which rules out underdamped overshoot — the remaining wobble was pixel
    // rounding, handled in Workspaces.qml itself.
    readonly property real frameSpringWorkspaceStiffness: 920
    readonly property real frameSpringWorkspaceDamping: 50
    readonly property real frameSpringWorkspaceMass: 0.6
}
