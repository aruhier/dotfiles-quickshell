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

    // Hidden with no default sink, rather than a low-volume glyph at 0%.
    contentVisible: AudioService.ready
    contentWidth: content.implicitWidth

    // Icon vertical nudge / size bias — see Icon.qml.
    readonly property real iconVerticalOffset: 0.5
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.iconLabelSpacing

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            color: root.textColor
            text: AudioService.icon
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            // Muted replaces the whole format: icon only, no percent.
            visible: !root.muted
            color: root.textColor
            text: root.pct + "%"
        }
    }

    NotchWheelArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["pavucontrol"])
        onStepped: (notches) => AudioService.bumpPct(notches * root.step)
    }
}
