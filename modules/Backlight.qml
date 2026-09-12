pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.shared

// Screen-brightness indicator — a thin view over BacklightService, which owns
// the actual /sys/class/backlight reading. Hides itself when there's no
// backlight device (e.g. external monitors only).
BarModule {
    id: root

    readonly property real percent: BacklightService.percent
    readonly property bool available: BacklightService.available

    contentVisible: available
    contentWidth: content.implicitWidth

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 1.0
    readonly property real iconSizeRatio: 1.0

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.groupText
            text: Math.round(root.percent) + "%"
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            text: BacklightService.icon
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (!root.available)
                return;
            BacklightService.bump(event.angleDelta.y > 0 ? 1 : -1);
        }
    }
}
