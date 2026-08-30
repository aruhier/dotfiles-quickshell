import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../shared"

// Mirrors waybar's "pulseaudio" module (backed by pipewire-pulse here).
Item {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.ready && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.ready && sink.audio ? sink.audio.volume : 0

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    implicitWidth: content.implicitWidth + 12
    implicitHeight: Theme.barHeight
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.resizeDuration
            easing.type: Theme.resizeEasing
        }
    }

    readonly property int pct: Math.round(volume * 100)

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 0.5
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize(root.iconSizeRatio)
            color: Theme.groupText
            // waybar's "format-muted" replaces the whole format while muted.
            text: root.muted ? "󰝟" : root.pct < 33 ? "󰕿" : root.pct < 66 ? "󰖀" : "󰕾"
        }

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
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
            var step = 0.05;
            var v = root.sink.audio.volume + (event.angleDelta.y > 0 ? step : -step);
            root.sink.audio.volume = Math.max(0, Math.min(1, v));
        }
    }
}
