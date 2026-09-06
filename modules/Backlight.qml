pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.shared

// Screen-brightness indicator. Actual /sys/class/backlight reading lives in
// services/BacklightService.qml (singleton, one watch/read cycle for the whole
// process regardless of monitor count); this is just a thin view over that
// shared state. Hides itself when there's no backlight device (e.g. external
// monitors).
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
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.groupText
            text: Math.round(root.percent) + "%"
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            text: root.percent < 50 ? "󰃞" : "󰃠"
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
