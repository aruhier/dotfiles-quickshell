import QtQuick
import Quickshell.Hyprland
import "../shared"

// Mirrors waybar's "hyprland/submap" module: hidden on the default submap,
// shows an italic pill with the submap name otherwise.
Rectangle {
    id: root

    property string submap: ""

    visible: submap.length > 0
    color: Theme.accent
    radius: height / 2
    // Unconditional — see Mpd.qml for why gating width on the same
    // property as `visible` breaks visibility.
    implicitWidth: label.implicitWidth + 16
    implicitHeight: Theme.barHeight - 4
    clip: true

    Behavior on implicitWidth {
        SpringAnimation {
            spring: Theme.springSpring
            damping: Theme.springDamping
            epsilon: Theme.springEpsilon
        }
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
