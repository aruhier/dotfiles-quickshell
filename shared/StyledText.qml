pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// Every piece of text in this shell, so the four things that are the same at
// all ~65 text sites aren't a convention someone has to remember:
//
//  - `renderType: Text.NativeRendering`. The default SDF renderer shows
//    visible chromatic fringing here, so a missed opt-in is a subtle rendering
//    regression nobody would report. (Quickshell 0.3.1 documents a global
//    `//@ pragma NativeTextRendering` that would cover this one line; not used,
//    because the other three still need a type and splitting them would be
//    worse than keeping all four here.)
//  - `font.family`. QML takes one family, not a fallback chain, and getting it
//    wrong silently drops Latin text onto a narrower face.
//  - a default `font.pixelSize`, so a site that doesn't care doesn't pick.
//  - weight, through Inter's `wght` axis rather than `font.weight`. See below.
//
// Colour is deliberately not unified: the bar pills, hover popups and
// notification surfaces have separate palettes, so every site states it.
// Theme.text is only the fallback for a site that says nothing at all.
Text {
    // Weight goes through the variable axis, never `font.weight`, `font.bold`
    // or `font.styleName`. fontconfig exposes InterVariable.ttf as nine named
    // instances (Thin..Black, wght 100..900 in hundreds) and Qt matches
    // against those, so by-number requests land on a face nobody designed:
    // `font.weight: 450` and `font.weight: 500` both render pixel-identical to
    // Regular, and `font.bold` doesn't reach the Bold instance at all — Qt
    // synthesises bold off the 400 outline instead (measured at 12px: 126px
    // advance and 472 units of ink, against 130px and 479 for the real face
    // the axis selects). `font.variableAxes` sets FreeType variation coords
    // directly, so any value in between is the weight Inter was drawn for.
    //
    // 450 rather than 400 because Inter reads thin at this size on these
    // screens. It is a designed weight, unlike a rasterizer-level embolden
    // (FREETYPE_PROPERTIES stem darkening): FreeType only compensates
    // correctly for that with linear alpha blending and gamma correction,
    // which Qt doesn't do, so it just comes out heavy and fuzzy.
    //
    // An axis set here wins over `font.bold`/`font.styleName` at the site —
    // and worse, silently: `font.bold: true` on top of this re-synthesises
    // bold from the 450 outline (504 units of ink, heavier and smeared), and
    // `font.styleName: "ExtraBold"` renders at 450. So sites set `bold` or
    // `wght` instead; both are below.
    property bool bold: false
    property int wght: bold ? Theme.fontWeightBold : Theme.fontWeight

    // Vertical-only hinting, i.e. snap horizontal edges (baseline, x-height)
    // to the pixel grid and leave stem positions alone. Without an explicit
    // preference Qt Quick's native text path loads glyphs fully unhinted —
    // fontconfig's system-wide `hintslight`
    // (/etc/fonts/conf.d/10-hinting-slight.conf) is what waybar and GTK get,
    // and it never reaches a QQuickText — so this is the setting that makes
    // the bar render the way the rest of the desktop already does.
    //
    // `Font.PreferFullHinting` was tried and reverted. It is measurably
    // crisper (share of a label's ink in fully-covered pixels: 53.5% unhinted,
    // 55.6% here, 62.5% full) but at 12px it visibly mangles Inter: advances
    // round to whole pixels so letter spacing goes uneven, `p` grows a hard
    // 1px descender spur, `S`/`5` go blocky, and Nerd Font glyphs lose thin
    // strokes outright — the notification bell loses both motion arcs. The
    // crispness is not worth the shapes. Vertical-only keeps every glyph the
    // shape it was drawn as, which is why `Icon.qml` needs no opt-out from it.
    font.hintingPreference: Font.PreferVerticalHinting
    renderType: Text.NativeRendering
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.variableAxes: ({ "wght": wght })
    color: Theme.text
}
