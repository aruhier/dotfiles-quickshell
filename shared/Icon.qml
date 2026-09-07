pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// A Nerd Font glyph: same text stack as StyledText, but sized off
// Theme.iconSize rather than Theme.fontSize, since icon glyphs render smaller
// than Latin text at the same pixelSize — and glyph sets differ from each
// other again, hence the per-module `sizeRatio` bias.
//
// Anchoring is left to the call site on purpose: an icon beside a label wants
// verticalCenter with a per-glyph nudge, one in a popup wants a
// Layout.alignment. Only the font stack is shared here.
StyledText {
    property real sizeRatio: 1.0

    font.pixelSize: Theme.iconSize(sizeRatio)
    color: Theme.groupText
}
