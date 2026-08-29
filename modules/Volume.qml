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

    implicitWidth: label.implicitWidth + 12
    implicitHeight: theme.barHeight

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.groupText
        text: {
            // waybar's "format-muted" is a standalone format (icon only,
            // no volume%) that replaces "format" entirely while muted.
            if (root.muted)
                return "󰝟";
            var pct = Math.round(root.volume * 100);
            var icon = pct < 33 ? "󰕿" : pct < 66 ? "󰖀" : "󰕾";
            return icon + "  " + pct + "%";
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
