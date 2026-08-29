import QtQuick
import Quickshell.Io

// Mirrors waybar's "backlight" module. Reads /sys/class/backlight directly
// like waybar does; hides itself when there is no backlight device
// (e.g. this desktop's external monitors, same as it behaves today).
Item {
    id: root

    required property var theme

    property real percent: 0
    property bool available: false

    visible: available
    // Unconditional (not "available ? label.implicitWidth + 12 : 0"): see
    // Mpd.qml for why gating this on `visible`/`available` while reading a
    // child's implicitWidth breaks visibility.
    implicitWidth: label.implicitWidth + 12
    implicitHeight: theme.barHeight

    Text {
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.groupText
        text: Math.round(root.percent) + "% " + (root.percent < 50 ? "󰃞" : "󰃠")
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
