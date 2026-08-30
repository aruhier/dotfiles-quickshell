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
    // Not from style.css — an intentional enhancement beyond waybar parity
    // (see Workspaces.qml): the background for a workspace that's active on
    // its own monitor but isn't the system-wide focused one, sitting
    // visually between an ordinary populated workspace (workspaceBg) and
    // the focused/active one (accent). 50% accent tinted over workspaceBg.
    readonly property color workspaceActiveBg: Qt.tint(workspaceBg, Qt.rgba(accent.r, accent.g, accent.b, 0.5))

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
    // Nerd Font glyphs rendered via Qt's automatic per-glyph fallback (see
    // fontFamily's note above) come out visually smaller than Latin text at
    // the same pixelSize — Pango's cascade in real waybar doesn't have this
    // gap even though its CSS is a flat 12px everywhere. Every module that
    // pairs an icon glyph with a text label sizes the glyph off this instead
    // of fontSize to compensate. Empirical value, not derived from waybar's
    // CSS (which has no separate icon size) — re-tune by eye if it drifts.
    readonly property int iconFontSize: 15

    // Per-module icon-glyph size bias: a module multiplies iconFontSize by
    // its own ratio (1.0 = no change, the default) when its specific glyph
    // needs to read bigger/smaller than every other module's icon — e.g. one
    // glyph looking visually smaller than its neighbors despite the shared
    // pixelSize. The ratio itself is a per-module tuning knob and lives on
    // the module (a local property next to the Text it sizes), not here —
    // this just centralizes the base value so modules don't hand-roll the
    // math. Only modules that need a bias call this; everyone else keeps
    // using iconFontSize directly.
    //
    // Deliberately not rounded to an int: Text.font.pixelSize is a real
    // property here (confirmed empirically — a fractional value loads with
    // no QML type error, unlike an actually int-typed property), and on a
    // fractionally-scaled output (e.g. DP-1 at 1.25x) rounding to a whole
    // logical pixel first then letting the compositor scale it can land on a
    // different physical size than handing Qt the precise fractional value
    // up front. Let Qt's own text layer handle the fractional size.
    function iconSize(ratio) {
        return iconFontSize * (ratio === undefined ? 1.0 : ratio);
    }

    readonly property int barHeight: 22
    // #waybar > box's border-bottom: 3px solid — genuine extra height below
    // the 22px content area, not an overlay on top of it.
    readonly property int barBorderHeight: 3

    // One-sided inner-edge pad for the left/right groups: style.css's
    // `.modules-left { border-width: 0 12px 0 0; }` / `.modules-right
    // { border-width: 0 0 0 12px; }` — only the side facing the center gets
    // it, the flush/outer edge gets none (see Bar.qml's leftGroup/rightGroup).
    readonly property int groupEdgePadding: 12
    // A flush-edge module's own CSS `margin: 0 4px` (see the shared
    // `#clock, #mpd, ...` rule in style.css) — used only where a module
    // sits directly against the true screen edge and needs this modeled
    // explicitly (see Bar.qml's rightGroup/leftGroup comments).
    readonly property int moduleOuterMargin: 4
    // .modules-center's cream pill caps: a fixed 15px border-left/right on
    // the container itself, independent of the buttons inside (see
    // Workspaces.qml).
    readonly property int centerCapWidth: 15

    // Shared "smooth resize" tuning: modules whose content changes size
    // (mpd title length, volume%, tray icon count, ...) ease their
    // implicitWidth through this instead of snapping. This alone is enough
    // to reflow the whole bar smoothly with no per-container animation
    // needed: each RowLayout's own implicitWidth (and in turn leftGroup/
    // rightGroup's, which just bind to it) is a plain expression that
    // re-reads its children's implicitWidth, so it — and everything
    // downstream — recomputes on every animation frame for free.
    readonly property int resizeDuration: 150
    readonly property int resizeEasing: Easing.OutCubic
}
