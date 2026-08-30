import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Mirrors waybar's "pulseaudio" module (backed by pipewire-pulse here).
Item {
    id: root

    required property var theme

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.ready && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.ready && sink.audio ? sink.audio.volume : 0

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    implicitWidth: content.implicitWidth + 12
    implicitHeight: theme.barHeight

    readonly property int pct: Math.round(volume * 100)

    // Nudges the icon down from its box-center — see Mpd.qml's
    // iconVerticalOffset for why. Tuned per module.
    readonly property real iconVerticalOffset: 0.5

    // Bias against the shared iconFontSize — see Theme.qml's iconSize().
    // 1.0 = no change; no bias needed here.
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            renderType: Text.NativeRendering
            // Box-centered against the Row, not baseline — see Mpd.qml.
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.iconSize(root.iconSizeRatio)
            color: root.theme.groupText
            // waybar's "format-muted" is a standalone format (icon only,
            // no volume%) that replaces "format" entirely while muted.
            text: root.muted ? "󰝟" : root.pct < 33 ? "󰕿" : root.pct < 66 ? "󰖀" : "󰕾"
        }

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.muted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
            color: root.theme.groupText
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
