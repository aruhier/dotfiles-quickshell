pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.shared
import qs.themes

// Volume indicator — a thin view over AudioService, which owns the default
// sink and the writes.
BarModule {
    id: root

    readonly property bool muted: AudioService.muted
    readonly property int pct: AudioService.pct

    // One wheel notch, in percentage points.
    readonly property int step: 5

    contentWidth: content.implicitWidth

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 0.5
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            text: AudioService.icon
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            // Muted replaces the whole format: icon only, no percent.
            visible: !root.muted
            color: Theme.groupText
            text: root.pct + "%"
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["pavucontrol"])
        onWheel: (event) => {
            AudioService.bumpPct(event.angleDelta.y > 0 ? root.step : -root.step);
        }
    }
}
