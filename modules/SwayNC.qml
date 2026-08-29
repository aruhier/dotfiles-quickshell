import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors waybar's "custom/swaync" module: subscribes to
// `swaync-client -swb` for live notification-center state.
Item {
    id: root

    required property var theme

    property string count: "0"
    property string alt: "none"

    readonly property var icons: ({
        "notification": "󰂞",
        "none": "󰂚",
        "dnd-notification": "󰂛",
        "dnd-none": "󰂛"
    })
    readonly property var iconColors: ({
        "notification": "#F98AA4",
        "none": theme.groupText,
        "dnd-notification": "#F98AA4",
        "dnd-none": "#9c9ca4"
    })

    implicitWidth: label.implicitWidth + 12
    implicitHeight: theme.barHeight

    Text {
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize + 1
        color: root.iconColors[root.alt] || root.theme.groupText
        text: root.icons[root.alt] || root.icons["none"]
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
            else
                Quickshell.execDetached(["swaync-client", "-d", "-sw"]);
        }
    }

    Process {
        id: subscribe
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line)
                    return;
                try {
                    var obj = JSON.parse(line);
                    root.count = obj.text;
                    root.alt = obj.alt;
                } catch (e) {
                    // ignore malformed lines
                }
            }
        }
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer
        interval: 5000
        onTriggered: subscribe.running = true
    }
}
