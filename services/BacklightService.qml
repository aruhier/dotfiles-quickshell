pragma Singleton
import QtQuick
import Quickshell.Io

// Shared backlight state for the whole process with exponential perceptual scaling.
QtObject {
    id: root

    property real percent: 0
    property bool available: false

    // Waybar default exponent is 2.0 (quadratic). Increase to 3.0 for steeper low-end control.
    property real exponent: 2.75

    function bump(delta) {
        // Option A: Let brightnessctl handle exponential step natively if supported
        bumpProc.exec(["sh", "-c", "brightnessctl set " + delta + " --exponent=" + exponent + " >/dev/null 2>&1 || true"]);
    }

    function refresh() {
        pollProc.running = false;
        pollProc.running = true;
    }

    property Process bumpProc: Process {
        id: bumpProc
        onExited: root.refresh()
    }

    property Process pollProc: Process {
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
                    // Linear ratio (0.0 to 1.0)
                    var linearRatio = Math.max(0, Math.min(1, cur / max));

                    // Convert linear backlight ratio to exponential perceptual percent
                    // P_perceptual = (cur / max) ^ (1 / exponent) * 100
                    root.percent = Math.pow(linearRatio, 1.0 / root.exponent) * 100;
                    root.available = true;
                } else {
                    root.available = false;
                }
            }
        }
    }

    property Timer pollTimer: Timer {
        id: pollTimer
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
