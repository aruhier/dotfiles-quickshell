import QtQuick

// Color palette mirrored from ~/dotfiles/waybar/style.css so the quickshell
// bar looks like the waybar setup it replaces.
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

    readonly property color critical: "#f53c3c"
    readonly property color privacyActive: "#D14005"

    // waybar's style.css lists a font-family fallback chain (Nerd Font Mono,
    // Inter Variable, Material Design Icons) and Pango picks per-character
    // from it. QML's `font.family` only takes a single family — feeding it
    // the whole comma-joined CSS string doesn't give a real cascade, Qt
    // fuzzy-resolves it to just "Symbols Nerd Font Mono" (confirmed via
    // `fc-match`), and since that font has no Latin glyphs, plain text
    // (workspace labels, clock, etc.) silently fell back to a different,
    // narrower font than waybar's Inter Variable — every workspace button
    // rendered visibly narrower than waybar's, with visible seams besides
    // (see Workspaces.qml's antialiasing note). `font.families` (the Qt 6.1+
    // list property) would be the correct fix but isn't exposed on this
    // build's QML Text font value type ("Cannot assign to non-existent
    // property families"). Using Inter Variable as the sole family instead
    // works because Qt auto-falls-back per missing glyph to another
    // installed font for codepoints it doesn't cover (confirmed: Nerd Font
    // icons still render) — so normal text gets correct Inter metrics and
    // icons still resolve via Qt's own fallback, without needing an
    // explicit list.
    readonly property string fontFamily: "Inter Variable"
    readonly property int fontSize: 12
    readonly property int barHeight: 22
    // #waybar > box's border-bottom: 3px solid — genuine extra height below
    // the 22px content area, not an overlay on top of it.
    readonly property int barBorderHeight: 3

    // One-sided inner-edge pad for the left/right groups: style.css's
    // `.modules-left { border-width: 0 12px 0 0; }` / `.modules-right
    // { border-width: 0 0 0 12px; }` — only the side facing the center gets
    // it, the flush/outer edge gets none (see Bar.qml's leftGroup/rightGroup).
    readonly property int groupEdgePadding: 12
    // .modules-center's cream pill caps: a fixed 15px border-left/right on
    // the container itself, independent of the buttons inside (see
    // Workspaces.qml).
    readonly property int centerCapWidth: 15
}
