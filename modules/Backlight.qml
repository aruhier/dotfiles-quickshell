import QtQuick
import Quickshell.Io

// Mirrors waybar's "backlight" module. Reads /sys/class/backlight directly;
// hides itself when there's no backlight device (e.g. external monitors).
Item {
    id: root

    required property var theme

    property real percent: 0
    property bool available: false

    visible: available
    // Unconditional, not gated on `available`: see Mpd.qml for why gating
    // width on the same property as `visible` breaks visibility.
    implicitWidth: content.implicitWidth + 12
    implicitHeight: theme.barHeight
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
        }
    }

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 2
    readonly property real iconSizeRatio: 1.0

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
            color: root.theme.groupText
            text: Math.round(root.percent) + "%"
        }

        Text {
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.iconSize(root.iconSizeRatio)
            color: root.theme.groupText
            text: root.percent < 50 ? "󰃞" : "󰃠"
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (!root.available)
                return;
            bumpProc.exec(["sh", "-c", "brightnessctl set " + (event.angleDelta.y > 0 ? "+5%" : "5%-") + " >/dev/null 2>&1 || true"]);
        }
    }

    Process {
        id: bumpProc
        onExited: pollProc.running = true
    }

    Process {
        id: pollProc
        command: ["sh", "-c", "d=$(ls /sys/class/backlight 2>/dev/null | head -1); if [ -n \"$d\" ]; then cur=$(cat /sys/class/backlight/$d/brightness); max=$(cat /sys/class/backlight/$d/max_brightness); echo \"$cur $max\"; fi"]
        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                var out = collector.text.trim();
                if (!out) {
                    root.available = false;
                    return;
                }
                var parts = out.split(" ");
                var cur = parseFloat(parts[0]);
                var max = parseFloat(parts[1]);
                if (max > 0) {
                    root.percent = (cur / max) * 100;
                    root.available = true;
                } else {
                    root.available = false;
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pollProc.running = false;
            pollProc.running = true;
        }
    }
}
