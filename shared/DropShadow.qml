pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// The one drop shadow every placed plate casts (the OSD pill casts none,
// notes/osd.md). `source` is a bare plate, never text: it is rendered into a
// texture, which blurs text at fractional scale (notes/text.md). A plate over
// the desktop is hidden, so only the effect paints it (notes/notifications.md).
MultiEffect {
    required source
    anchors.fill: source
    shadowEnabled: true
    shadowColor: "black"
    shadowOpacity: 0.4
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 1
    shadowBlur: 0.4
}
