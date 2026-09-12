pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations

// A glyph that answers clicks, shrinks while held and turns accent-coloured
// under the cursor, so every pressable icon shares one feel. Set
// text/color/font.pixelSize as on any StyledText; `color` is the rest colour
// and the hover colour lays over it. StyledText rather than Icon, since call
// sites set their own pixelSize and palette. The gate is `interactive`, not
// `enabled`: that one is QQuickItem's and would disable the subtree.
StyledText {
    id: button

    property bool interactive: true
    property color hoverColor: Theme.accent
    // Extra hit area around the glyph, for small ones like the month arrows.
    property int hitPadding: 0
    readonly property bool hovered: hover.hovered
    signal activated

    scale: press.value

    // A `when` Binding, not a `color:` expression: call sites bind `color`
    // themselves and would override one here. This lays the hover colour over
    // whatever they bound, and restores it after.
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

    // A HoverHandler, not `hoverEnabled` above: MouseArea hover is exclusive
    // and would steal it from an enclosing surface, closing a HoverPopup under
    // the cursor.
    HoverHandler {
        id: hover
        margin: button.hitPadding
    }
}
