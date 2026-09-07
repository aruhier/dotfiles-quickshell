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
}
