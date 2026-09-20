pragma ComponentBehavior: Bound
import QtQuick
import qs.themes

// Every piece of text in this shell. A bare `Text {}` is a bug: the four
// settings below are identical at all ~65 sites, and three of them fail
// silently when missed — chromatic fringing from the SDF renderer, Latin text
// dropping onto a narrower face, and a weight that never reaches the face it
// names. Colour is not unified: the bar pills, hover popups and notification
// surfaces have separate palettes, so every site states it.
Text {
    // Sites set `bold` or `wght`, never `font.weight`, `font.bold` or
    // `font.styleName`: Qt matches those against the nine named instances
    // fontconfig exposes, so a by-number weight lands on a face nobody
    // designed and `font.bold` gets a synthesised smear off the 400 outline.
    // The axis below sets FreeType variation coords directly, and silently
    // overrides all three if a site sets one anyway. Details and measurements:
    // notes/text.md, "Text weight goes through Inter's `wght` axis".
    property bool bold: false
    property int wght: bold ? Theme.fontWeightBold : Theme.fontWeight

    // Snap baselines and x-heights to the pixel grid, leave stems alone.
    // Required explicitly: Qt Quick's native text path loads glyphs fully
    // unhinted, and fontconfig's system-wide hintslight never reaches a
    // QQuickText. Don't "upgrade" to PreferFullHinting — it is crisper but
    // mangles Inter at 12px; see notes/text.md, "Text is unhinted unless an item
    // says so".
    font.hintingPreference: Font.PreferVerticalHinting
    renderType: Text.NativeRendering
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.variableAxes: ({ "wght": wght })
    color: Theme.text
}
