pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.themes

// A Nerd Font glyph: StyledText's stack sized off Theme.iconSize, since icon
// glyphs render smaller than Latin text at the same pixelSize — and glyph sets
// differ again, hence `sizeRatio`. Anchoring stays with the call site: beside a
// label it wants a per-glyph nudge, in a popup a Layout.alignment. So does
// colour: a bar module passes its `textColor`, so it follows the group's.
//
// Bar modules tune two knobs, by eye, for the glyph beside their label:
// `iconVerticalOffset` (a glyph's ink sits above its box's centre next to
// text) and `iconSizeRatio` (some glyph sets read small). Kept at 0 / 1.0 too.
StyledText {
    property real sizeRatio: 1.0

    font.pixelSize: Theme.iconSize(sizeRatio)
    color: Theme.groupText
}
