import QtQuick
import QtQuick.Effects

// The drop shadow every placed plate carries — a toast, a control-centre
// card, the control centre itself — so they all cast the same one. A shadow
// is elevation, not material: the OSD pill shares the toasts' glass and
// deliberately casts none (notes/osd.md). `source` is the plate and nothing
// else: the effect renders its source
// into a texture, and text inside one resamples at fractional scale
// (notes/text.md). Nor is the source excluded from ordinary painting: a
// translucent plate left visible is drawn twice and its alphas compound
// (notes/notifications.md), so a plate over the desktop is hidden and the
// effect is the one thing that paints it.
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
