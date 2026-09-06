pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// A Nerd Font glyph. Same text stack as StyledText (which it derives from),
// but sized off Theme.iconSize rather than Theme.fontSize: icon glyphs render
// smaller than Latin text at the same pixelSize, and individual glyph sets
// are off again from each other — hence `sizeRatio`, the per-module bias that
// every module used to spell out as `font.pixelSize: Theme.iconSize(root.iconSizeRatio)`.
//
// Anchoring is left to the call site on purpose. An icon next to a label
// wants verticalCenter against its Row (with a per-glyph nudge, since ink
// mass and box geometry disagree), one in a popup wants a Layout.alignment,
// and a type that set its own anchors would have to be fought off in half of
// those. Only the font stack is shared here.
StyledText {
    property real sizeRatio: 1.0

    font.pixelSize: Theme.iconSize(sizeRatio)
    color: Theme.groupText
}
