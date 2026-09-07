pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.shared

// Volume indicator (backed by pipewire-pulse).
BarModule {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.ready && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.ready && sink.audio ? sink.audio.volume : 0
    readonly property int pct: Math.round(volume * 100)

    // One wheel notch.
    readonly property real step: 0.05

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

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
            // Muted replaces the whole format: icon only, no percent.
            text: root.muted ? "󰝟" : root.pct < 33 ? "󰕿" : root.pct < 66 ? "󰖀" : "󰕾"
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
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
            if (!root.sink || !root.sink.audio)
                return;
            const next = root.sink.audio.volume + (event.angleDelta.y > 0 ? root.step : -root.step);
            root.sink.audio.volume = Math.max(0, Math.min(1, next));
        }
    }
}
