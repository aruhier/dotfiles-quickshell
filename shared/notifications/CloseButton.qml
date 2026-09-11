pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations
import qs.shared.notifications

// The round ✕ chip: a card's close button and a group's close-all.
//
// Implicit size only, never width/height, so it works both anchored into a
// card's corner and as a plain RowLayout child needing no Layout.preferred*.
Rectangle {
    id: button

    property int diameter: 18
    // Shares a literal with Theme.popupBg by coincidence, not by meaning.
    property color restColor: "black"
    // Accent-lit on hover like every other clickable — see AGENTS.md's
    // PressableIcon rule; the chip's fill is what lights up here, so the
    // glyph goes dark for contrast against it.
    property color hoverColor: Theme.accent
    property color glyphColor: NotificationTheme.text
    property color glyphHoverColor: "black"
    // Proportional to the chip; the card's button overrides it.
    property int glyphSize: Math.round(button.diameter * 0.55)
    property bool interactive: true

    signal activated

    implicitWidth: diameter
    implicitHeight: diameter
    // Off `diameter`, not `height`: a RowLayout can stretch this past its
    // implicit height, and the sites it replaced pinned radius to the nominal.
    radius: diameter / 2
    color: restColor
    scale: press.value

    // Two sites reveal on hover via `opacity`; inert at the third.
    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }

    PressSpring {
        id: press
        pressed: area.pressed
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: button.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.activated()
    }

    // Over the base rather than swapping `color`, as the sites did.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: area.containsMouse
        color: button.hoverColor
    }

    StyledText {
        anchors.centerIn: parent
        text: "✕"
        color: area.containsMouse ? button.glyphHoverColor : button.glyphColor
        font.pixelSize: button.glyphSize
    }
}
