import QtQuick
import Quickshell
import "../services"

// Mirrors waybar's "custom/swaync" module. The actual `swaync-client -swb`
// subscription lives in services/SwayNCService.qml (a singleton) so there's
// exactly one subscription for the whole qs process, not one per
// monitor/Bar — this is just a thin view over that shared state.
Item {
    id: root

    required property var theme

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
        "none": theme.groupText,
        "dnd-notification": "#F98AA4",
        "dnd-none": "#9c9ca4"
    })

    implicitWidth: label.implicitWidth + 12
    implicitHeight: theme.barHeight
    // Smooth resize — see Theme.qml's resizeDuration.
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
        }
    }

    // Nudges the icon down from its box-center — see Mpd.qml's
    // iconVerticalOffset for why. Tuned per module.
    readonly property real iconVerticalOffset: 0

    // Bias against the shared iconFontSize — see Theme.qml's iconSize().
    // 1.0 = no change; no bias needed here.
    readonly property real iconSizeRatio: 0.9

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.iconVerticalOffset
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.iconSize(root.iconSizeRatio)
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
}
