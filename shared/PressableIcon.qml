pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations

// A glyph that answers clicks and shrinks while held, so every pressable icon
// shares one feel. Set text/color/font.pixelSize as on any StyledText.
//
// StyledText, not Icon: call sites set their own pixelSize and palette, both
// of which Icon owns.
//
// The gate is `interactive`, not `enabled` — `enabled` is QQuickItem's own,
// and shadowing it would disable the subtree. Same trap as `state` in Mpd.qml.
StyledText {
    id: button

    property bool interactive: true
    // Opt-in: hover tracking is off by default so the existing sites keep
    // their exact behaviour; a site that wants a hover colour sets this and
    // reads `hovered`.
    property bool trackHover: false
    readonly property bool hovered: hover.hovered
    signal activated

    scale: press.value

    PressSpring {
        id: press
        pressed: area.pressed
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: button.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: button.activated()
    }

    // A HoverHandler, not `hoverEnabled` on the MouseArea above: MouseArea
    // hover is exclusive, so enabling it here would steal the hover from an
    // enclosing hover-tracked surface — a HoverPopup's own MouseArea would see
    // containsMouse drop and close the popup under the cursor. HoverHandler
    // is non-blocking and leaves the parent's hover intact.
    HoverHandler {
        id: hover
        enabled: button.trackHover
    }
}
