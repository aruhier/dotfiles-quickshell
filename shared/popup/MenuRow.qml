pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.themes

// One choice in a popup menu, highlighted by a fill under the cursor rather
// than accent text: teal means "on" here, and a hovered row mustn't read as a
// state. Its popup sets `padding: 4` and `spacing: 0`. See notes/style.md.
Item {
    id: row

    property alias text: label.text
    // Trailing state text, e.g. "On"; empty for none.
    property alias value: valueLabel.text
    property color valueColor: Theme.text
    // Extra label inset, for rows grouped under a heading.
    property int indent: 0
    // Text inset from either side; a menu heading lines up on it.
    readonly property int inset: 10
    signal activated

    Layout.fillWidth: true
    implicitHeight: 28
    implicitWidth: label.implicitWidth + valueLabel.implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: hover.hovered ? Theme.groupBg : "transparent"
    }

    StyledText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: row.inset + row.indent
        color: Theme.textBright
    }

    StyledText {
        id: valueLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: row.inset
        color: row.valueColor
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }

    // A HoverHandler, not `hoverEnabled` above: MouseArea hover is exclusive
    // and would steal it from the popup's surface, closing it under the cursor.
    HoverHandler {
        id: hover
    }
}
