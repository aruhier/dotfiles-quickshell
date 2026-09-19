pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.shared

// Hyprland submap indicator: an italic label, hidden on the default submap.
// The cream pill and the text colour on it are the group's, not this
// module's: shell.qml's layout puts it in its own ModuleGroup, which slides
// away with it.
BarModule {
    id: root

    property bool active: false
    // The last submap's name, kept after it ends so the label is still there
    // while the group collapses over it.
    property string submap: ""
    // A submap name is a mode indicator, not a message.
    readonly property int maxLength: 30

    contentVisible: active
    contentWidth: label.implicitWidth

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.submap
        font.italic: true
        bold: true
        color: root.textColor
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "submap")
                return;
            root.active = event.data.length > 0;
            if (root.active)
                root.submap = event.data.substring(0, root.maxLength);
        }
    }
}
