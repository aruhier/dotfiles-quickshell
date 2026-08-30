import QtQuick
import Quickshell
import "../services"
import "../shared"

// Mirrors waybar's "custom/swaync" module. The actual `swaync-client -swb`
// subscription lives in services/SwayNCService.qml (singleton, one
// subscription for the whole process); this is just a thin view.
Item {
    id: root

    readonly property string count: SwayNCService.count
    readonly property string alt: SwayNCService.alt

    readonly property var icons: ({
        "notification": "󰂞",
        "none": "󰂚",
        "dnd-notification": "󰂛",
        "dnd-none": "󰂛"
    })
    readonly property var iconColors: ({
        "notification": "#F98AA4",
        "none": Theme.groupText,
        "dnd-notification": "#F98AA4",
        "dnd-none": "#9c9ca4"
    })

    implicitWidth: label.implicitWidth + 12
    implicitHeight: Theme.barHeight
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.resizeDuration
            easing.type: Theme.resizeEasing
        }
    }

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 0
    readonly property real iconSizeRatio: 0.9

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.iconVerticalOffset
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize(root.iconSizeRatio)
        color: root.iconColors[root.alt] || Theme.groupText
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
}
