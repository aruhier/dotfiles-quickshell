pragma Singleton
import QtQuick
import Quickshell.Io

// Shared mpd state for the whole process — one `mpc idleloop` subscription
// instead of one per monitor/Bar, and instead of polling on a fixed timer.
// `mpc idleloop <subsystem>` blocks on mpd's `idle` command and only prints
// when that subsystem changes; refresh() re-reads status/current on demand.
// Mpd.qml just reads these properties; only this singleton owns the
// Processes/Timer.
QtObject {
    id: root

    property string playbackState: "disconnected" // disconnected | stopped | playing | paused
    property string artist: ""
    property string title: ""

    function refresh() {
        statusProc.running = false;
        statusProc.running = true;
    }

    function applyStatus(text) {
        if (!text) {
            root.playbackState = "disconnected";
            return;
        }
        // The [state] line only appears when a song is loaded, so find it
        // by content rather than a fixed line index.
        var lines = text.split("\n");
        var hasVolumeLine = false;
        var stateLine = null;
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("volume:") === 0)
                hasVolumeLine = true;
            if (lines[i].indexOf("[") === 0)
                stateLine = lines[i];
        }
        if (!hasVolumeLine) {
            root.playbackState = "disconnected";
            return;
        }
        if (stateLine && stateLine.indexOf("[playing]") === 0) {
            root.playbackState = "playing";
        } else if (stateLine && stateLine.indexOf("[paused]") === 0) {
            root.playbackState = "paused";
        } else {
            root.playbackState = "stopped";
            root.artist = "";
            root.title = "";
            return;
        }

        currentTrackProc.running = false;
        currentTrackProc.running = true;
    }

    property Process statusProc: Process {
        id: statusProc
        command: ["mpc", "status"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: root.applyStatus(statusCollector.text)
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.playbackState = "disconnected";
        }
    }

    property Process currentTrackProc: Process {
        id: currentTrackProc
        command: ["mpc", "current", "-f", "%artist%\t%title%"]
        stdout: StdioCollector {
            id: currentCollector
            onStreamFinished: {
                var parts = currentCollector.text.replace(/\n$/, "").split("\t");
                root.artist = parts[0] || "";
                root.title = parts[1] || "";
            }
        }
    }

    // Long-lived subscription; restricted to "player" since that's the only
    // subsystem this module displays.
    property Process idleProc: Process {
        id: idleProc
        command: ["mpc", "idleloop", "player"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.refresh()
        }
        onExited: restartTimer.start()
    }

    // idleloop exits if mpd isn't running or drops the connection —
    // reconnect after a delay and re-sync state.
    property Timer restartTimer: Timer {
        id: restartTimer
        interval: 5000
        onTriggered: {
            idleProc.running = true;
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
