pragma Singleton
import QtQuick
import Quickshell.Io

// Shared swaync-client subscription for the whole process — one long-lived
// `swaync-client -swb` subscription instead of one per monitor/Bar. Also
// caps orphaned processes from an ungraceful shutdown at one instead of
// one-per-monitor. SwayNC.qml just reads these properties; only this
// singleton owns the Process/Timer.
QtObject {
    id: root

    property string count: "0"
    property string alt: "none"

    property Process subscribe: Process {
        id: subscribe
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line)
                    return;
                try {
                    var obj = JSON.parse(line);
                    root.count = obj.text;
                    root.alt = obj.alt;
                } catch (e) {
                // ignore malformed lines
                }
            }
        }
        onExited: restartTimer.start()
    }

    property Timer restartTimer: Timer {
        id: restartTimer
        interval: 5000
        onTriggered: subscribe.running = true
    }
}
