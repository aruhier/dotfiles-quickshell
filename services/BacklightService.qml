pragma Singleton
import QtQuick
import Quickshell.Io

// Shared backlight state for the whole process — one poll cycle (and one
// brightnessctl invocation) instead of one per monitor/Bar, since
// /sys/class/backlight is a single system-wide device regardless of how
// many outputs are connected. Backlight.qml just reads these properties and
// calls bump(); only this singleton owns the Processes/Timer.
QtObject {
    id: root

    property real percent: 0
    property bool available: false

    function bump(delta) {
        bumpProc.exec(["sh", "-c", "brightnessctl set " + delta + " >/dev/null 2>&1 || true"]);
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
                    root.percent = (cur / max) * 100;
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
