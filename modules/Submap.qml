import QtQuick
import Quickshell.Hyprland

// Mirrors waybar's "hyprland/submap" module: hidden on the default submap,
// shows an italic pill with the submap name otherwise.
Rectangle {
    id: root

    required property var theme

    property string submap: ""

    visible: submap.length > 0
    color: theme.accent
    radius: height / 2
    implicitWidth: visible ? label.implicitWidth + 16 : 0
    implicitHeight: theme.barHeight - 4

    Text {
        id: label
        anchors.centerIn: parent
        text: root.submap
        font.italic: true
        font.bold: true
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.accentText

        // waybar's max-length: 30
        readonly property int maxLength: 30
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.submap = event.data.length > 30 ? event.data.substring(0, 30) : event.data;
        }
    }
}
