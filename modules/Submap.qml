pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.shared

// Hyprland submap indicator: hidden on the default submap, an italic pill with
// the submap name otherwise.
BarModule {
    id: root

    property string submap: ""
    // A submap name is a mode indicator, not a message.
    readonly property int maxLength: 30

    contentVisible: submap.length > 0
    contentWidth: label.implicitWidth
    // Wider than the shared 12: this is a standalone accent pill rather than a
    // label inside a group, so it carries its own inset.
    padding: 16
    // Inset from the bar's full height, so the pill reads as sitting inside
    // the group rather than filling it.
    implicitHeight: Theme.barHeight - 4

    Rectangle {
        anchors.fill: parent
        color: Theme.accent
        radius: height / 2

        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.submap
            font.italic: true
            font.bold: true
            color: Theme.accentText
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.submap = event.data.substring(0, root.maxLength);
        }
    }
}
