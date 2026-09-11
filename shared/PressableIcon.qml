pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations

// A glyph that answers clicks, shrinks while held and turns accent-coloured
// under the cursor, so every pressable icon shares one feel. Set
// text/color/font.pixelSize as on any StyledText; `color` is the rest colour,
// the hover colour is applied over it.
//
// StyledText, not Icon: call sites set their own pixelSize and palette, both
// of which Icon owns.
//
// The gate is `interactive`, not `enabled` — `enabled` is QQuickItem's own,
// and shadowing it would disable the subtree. Same trap as `state` in Mpd.qml.
StyledText {
    id: button

    property bool interactive: true
    property color hoverColor: Theme.accent
    // Extra clickable/hoverable margin around the glyph, for small ones like
    // the calendar's month arrows.
    property int hitPadding: 0
    readonly property bool hovered: hover.hovered
    signal activated

    scale: press.value

    // A Binding with `when`, not a `color:` expression here: call sites bind
    // `color` themselves (an MPRIS toggle lights up when active), and a
    // binding in this file would just be overridden by theirs. `when` lays
    // the hover colour over whatever they bound and restores it after.
    Binding {
        target: button
        property: "color"
        value: button.hoverColor
        when: button.hovered && button.interactive
    }

    PressSpring {
        id: press
        pressed: area.pressed
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -button.hitPadding
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
        margin: button.hitPadding
    }
}
