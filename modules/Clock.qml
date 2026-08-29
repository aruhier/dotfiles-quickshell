import QtQuick
import "../shared"

// Mirrors waybar's "clock" module (format + tooltip-format).
Item {
    id: root

    required property var theme

    implicitWidth: label.implicitWidth + 12
    implicitHeight: theme.barHeight

    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.groupText
        text: "󰃭  " + Qt.formatDateTime(root.now, "ddd dd MMM  hh:mm")
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    Tooltip {
        anchorItem: root
        theme: root.theme
        show: hover.containsMouse
        text: "<b>" + Qt.formatDateTime(root.now, "yyyy MMMM") + "</b>"
    }
}
