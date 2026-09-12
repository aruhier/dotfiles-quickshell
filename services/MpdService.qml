pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Shared mpd state: one `mpc idleloop` subscription process-wide, and no
// polling timer — idleloop blocks until the subsystem actually changes.
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
        // The [state] line only appears with a song loaded, so match on
        // content rather than a line index.
        const lines = text.split("\n");
        let hasVolumeLine = false;
        let stateLine = null;
        for (let i = 0; i < lines.length; i++) {
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
                const parts = currentCollector.text.replace(/\n$/, "").split("\t");
                root.artist = parts[0] || "";
                root.title = parts[1] || "";
            }
        }
    }

    // Restricted to "player", the only subsystem displayed here.
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

    // idleloop exits when mpd isn't running or drops the connection.
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
