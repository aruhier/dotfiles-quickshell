pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// An Icon sized to its ink rather than its advance, with the ink flush left.
// Nerd Font glyphs sit at varying offsets in their cells, so a cell-sized icon
// carries a different, invisible margin per glyph. See notes/style.md.
Item {
    id: root

    property alias text: glyph.text
    property alias color: glyph.color
    property alias sizeRatio: glyph.sizeRatio

    implicitWidth: Math.ceil(metrics.tightBoundingRect.width)
    implicitHeight: glyph.implicitHeight

    TextMetrics {
        id: metrics
        font: glyph.font
        text: glyph.text
    }

    Icon {
        id: glyph
        x: -metrics.tightBoundingRect.x
    }
}
