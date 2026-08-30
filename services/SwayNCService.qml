pragma Singleton
import QtQuick
import Quickshell.Io

// Shared swaync-client subscription for the whole qs process — one long-lived
// `swaync-client -swb` subscription system-wide instead of one per
// monitor/Bar. SwayNC.qml (one instance per output) just reads these
// properties; only this singleton owns the Process/Timer.
//
// This being a *singleton* also caps how many orphaned `swaync-client -swb`
// processes an ungracefully-killed qs can leave behind at one-per-monitor
// (previously each Bar spawned its own subscription, so N monitors meant N
// orphans per bad shutdown instead of 1).
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
