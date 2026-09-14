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
    // A relative darken (Qt.darker() factor), not a flat color: every state
    // above stays distinguishable while hovered, and the dark label text
    // gains contrast rather than losing it.
    readonly property real workspaceHoverDarken: 1.15
    // Workspace hover preview: width only, height follows the monitor's
    // aspect ratio. The "desktop" behind the thumbnails is lighter than
    // popupBg, so the preview reads as a screen inside the chrome.
    readonly property int workspacePreviewWidth: 560
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

    // Per-module bias on iconFontSize (1.0 = no change), for glyph sets that
    // read bigger/smaller than their neighbours.
    function iconSize(ratio) {
        return iconFontSize * (ratio === undefined ? 1.0 : ratio);
    }

    // On-screen display: a pill on the focused output, near the bottom, for
    // volume/backlight/lock-key keybinds. Metrics only — its *colours* come
    // from shared/notifications/NotificationTheme.qml, because the OSD is the
    // same kind of floating surface as a toast rather than a bar pill.
    // osdRadius is half osdHeight, i.e. a stadium; keep them in step.
    readonly property int osdWidth: 420
    readonly property int osdHeight: 66
    readonly property int osdRadius: 33
    readonly property int osdPadding: 21
    readonly property int osdTrackHeight: 9
    readonly property int osdIconSize: 29
    // Slack inside the surface for the springs to overshoot into: either side
    // of the widest pill, and above the pill's resting place. Both the rise
    // and the opening deliberately spring past their target and settle back,
    // and a window clips its contents.
    readonly property int osdOvershoot: 32
    // How far the pill hops above its resting place as a wind-up before it
    // drops back under the edge. Deliberately near twice the bump the rise
    // lands with — that one is a damping ratio rather than a number, and
    // ~10px here — since the wind-up is the whole gesture rather than the
    // tail of one. Must stay inside osdOvershoot: the hop coasts ~5% past
    // this before the drop takes over. See notes/osd.md.
    readonly property int osdBump: 18
    // A share of the output's height, not a fixed margin, so it lands in the
    // same place on a 1440 and a 2160 panel. swayosd worked the same way —
    // `margin_bottom = height * (1 - top_margin)`, default 0.85, so 0.15. This
    // sits deliberately lower than that.
    readonly property real osdBottomEdgeFraction: 0.07

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

    // Spring constants for FrameSpring.qml, which integrates the
    // mass-spring-damper ODE directly.
    readonly property real frameSpringStiffness: 460
    readonly property real frameSpringDamping: 35
    readonly property real frameSpringMass: 0.6
    // Stops a spring once this close to its target instead of approaching it
    // forever. Tuned for pixel-scale values; springs on a 0..1 scale need
    // their own much smaller epsilon (see PressSpring.qml).
    readonly property real springEpsilon: 0.25

    // Faster variant for Workspaces.qml, whose pill/delegate/indicator widths
    // all move together: same damping ratio (ζ ≈ 1.05), roughly 2x the natural
    // frequency. Don't damp it further — the leftover wobble is pixel
    // rounding, handled in Workspaces.qml itself.
    readonly property real frameSpringWorkspaceStiffness: 920
    readonly property real frameSpringWorkspaceDamping: 50
    readonly property real frameSpringWorkspaceMass: 0.6
}
