pragma Singleton
import QtQuick

// Shared palette + metrics for the whole bar. Singleton: pure static data
// shared process-wide instead of one instance per output.
QtObject {
    readonly property color barBg: "#2d2d2d"
    readonly property color barBorder: "#6AA099"
    readonly property color text: "#A3A3AB"
    readonly property color textBright: "#E5D4CE"

    readonly property color groupBg: "#424242"
    readonly property color groupText: "#E5D4CE"

    readonly property color accent: "#6AA099"
    readonly property color accentText: "#2d2d2d"

    readonly property color workspaceBg: "#9BBFBA"
    readonly property color workspaceEmptyBg: "#E5D4CE"
    readonly property color workspaceEmptyText: "#252527"
    readonly property color workspaceUrgent: "#F98BA4"
    // Not in style.css: color for a workspace active on its own monitor but
    // not system-focused (between workspaceBg and accent). See Workspaces.qml.
    readonly property color workspaceActiveBg: Qt.tint(workspaceBg, Qt.rgba(accent.r, accent.g, accent.b, 0.5))

    readonly property color critical: "#f53c3c"
    readonly property color privacyActive: "#D14005"

    // QML's font.family takes one name, not a CSS fallback chain. Using
    // "Inter Variable" alone and relying on Qt's automatic per-glyph
    // fallback for Nerd Font icon codepoints (font.families isn't available
    // on this Qt build's Text type).
    readonly property string fontFamily: "Inter Variable"
    readonly property int fontSize: 12
    // Nerd Font glyphs render smaller than Latin text at the same pixelSize;
    // icon Text elements size off this instead of fontSize. Tuned by eye.
    readonly property int iconFontSize: 15

    // Per-module bias on iconFontSize (1.0 = no change) for glyphs that read
    // bigger/smaller than their neighbors. Ratio itself lives on the module.
    function iconSize(ratio) {
        return iconFontSize * (ratio === undefined ? 1.0 : ratio);
    }

    readonly property int barHeight: 22
    // Bottom border stripe: real extra height below the content area, not
    // an overlay.
    readonly property int barBorderHeight: 3

    // One-sided inner pad for left/right groups (style.css's
    // .modules-left/.modules-right border-width); flush edge gets none.
    readonly property int groupEdgePadding: 12
    // A flush-edge module's own `margin: 0 4px` from style.css's shared
    // module rule.
    readonly property int moduleOuterMargin: 4
    // .modules-center's pill caps: fixed 15px border on the container.
    readonly property int centerCapWidth: 15

    // Modules ease implicitWidth (and Workspaces' sliding indicator) through
    // a SpringAnimation instead of snapping when content size changes.
    // Hyprland's own spring config (mass: 0.6, stiffness: 460, damping: 35)
    // does NOT translate directly here — plugging those in broke the
    // animation entirely, so Qt's SpringAnimation evidently doesn't share
    // Hyprland's unit convention despite the same underlying ODE shape.
    // Back to the values that worked: modest spring, small damping.
    readonly property real springSpring: 4.0
    readonly property real springDamping: 0.4
    // Stops the spring once within this many px/units of the target,
    // instead of asymptotically approaching it forever.
    readonly property real springEpsilon: 0.25

    // Faster variant for Workspaces.qml's own resize (pill width, delegate
    // width, and the selection indicator's width, which must all stay in
    // sync with each other) — kept separate from springSpring/springDamping
    // so tuning it doesn't also speed up every other module's resize.
    // Same 2x-spring/proportional-damping bump as the earlier "snappier"
    // attempt on the shared constants, safe to try here now that
    // Workspaces.qml's double-spring fight (selection.x vs the pill resize)
    // is fixed and no longer around to make it read as jittery.
    readonly property real workspaceSpringSpring: 8.0
    readonly property real workspaceSpringDamping: 0.56

    // For shared/animations/FrameSpring.qml (frame-driven springs, immune
    // to Behavior/SpringAnimation's ~60Hz QUnifiedTimer cap — see its
    // header comment and AGENT.md's "capped near 60Hz" section). Different
    // units from springSpring/springDamping above: those tune Qt's
    // SpringAnimation formula, this implements the mass-spring-damper ODE
    // directly, so Hyprland's own physical constants are the right values
    // to use here (the ones the comment above notes did NOT translate to
    // SpringAnimation).
    readonly property real frameSpringStiffness: 460
    readonly property real frameSpringDamping: 35
    readonly property real frameSpringMass: 0.6

    // Faster FrameSpring variant for Workspaces.qml, mirroring the ~2x bump
    // workspaceSpringSpring/workspaceSpringDamping give the SpringAnimation
    // variant above: same damping ratio as frameSpringStiffness/
    // frameSpringDamping/frameSpringMass (ζ = damping / (2*sqrt(stiffness*
    // mass)) ≈ 1.05 for both), roughly 2x the natural frequency.
    //
    // Pushing this to ζ≈2 (damping 94) to fight reported wobble made it
    // *worse*, not better — which rules out classic underdamped overshoot
    // as the mechanism (more damping can only ever reduce real oscillation,
    // never worsen it) and points at something else — see Workspaces.qml's
    // pixel-rounding on its spring outputs instead. Reverted to this value.
    readonly property real frameSpringWorkspaceStiffness: 920
    readonly property real frameSpringWorkspaceDamping: 50
    readonly property real frameSpringWorkspaceMass: 0.6
}
