import QtQuick
import Quickshell.Hyprland
import "../shared"
import "../shared/animations"

// Hyprland submap indicator: hidden on the default submap, shows an italic
// pill with the submap name otherwise.
Rectangle {
    id: root

    property string submap: ""

    // Plain bool, not read back through `visible` — see Mpd.qml's
    // `contentVisible` for why (Loader/visible deadlock).
    readonly property bool contentVisible: submap.length > 0
    visible: contentVisible
    color: Theme.accent
    radius: height / 2
    // Unconditional — see Mpd.qml for why gating width on the same
    // property as `visible` breaks visibility.
    implicitWidth: label.implicitWidth + 16
    implicitHeight: Theme.barHeight - 4
    clip: true

    Behavior on implicitWidth {
        WidthSpring {}
    }

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.centerIn: parent
        text: root.submap
        font.italic: true
        font.bold: true
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.accentText

        // Submap names are truncated to 30 chars, see onRawEvent below.
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
