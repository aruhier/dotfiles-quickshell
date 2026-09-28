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
        root.rerun(statusProc);
    }

    // Never restarts a read in flight: killing it still delivers its partial
    // stdout, which reads as a wrong state. A request during a read marks it
    // dirty and re-runs it on exit, so the last state always lands.
    function rerun(proc) {
        if (proc.running)
            proc.dirty = true;
        else
            proc.running = true;
    }

    function rerunIfDirty(proc) {
        if (!proc.dirty)
            return;
        proc.dirty = false;
        proc.running = true;
    }

    function setDisconnected() {
        root.playbackState = "disconnected";
        root.artist = "";
        root.title = "";
    }

    function applyStatus(text) {
        if (!text) {
            root.setDisconnected();
            return;
        }
        // The [state] line only appears with a song loaded, so match on
        // content rather than a line index.
        const lines = text.split("\n");
        let hasVolumeLine = false;
        let stateLine = null;
        // `volume:` (even "n/a") is printed whenever mpd answered at all.
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("volume:"))
                hasVolumeLine = true;
            if (lines[i].startsWith("["))
                stateLine = lines[i];
        }
        if (!hasVolumeLine) {
            root.setDisconnected();
            return;
        }
        // A read started before idleloop's last exit may predate mpd going
        // down, so only a fresh one proves mpd is up.
        if (statusProc.idleExits === root.idleExits) {
            root.failures = 0;
            if (!idleProc.running) {
                restartTimer.stop();
                idleProc.running = true;
            }
        }
        if (stateLine && stateLine.startsWith("[playing]")) {
            root.playbackState = "playing";
        } else if (stateLine && stateLine.startsWith("[paused]")) {
            root.playbackState = "paused";
        } else {
            root.playbackState = "stopped";
            root.artist = "";
            root.title = "";
            return;
        }

        root.rerun(currentTrackProc);
    }

    property Process statusProc: Process {
        id: statusProc
        // A refresh() asked for while this was running; see rerun().
        property bool dirty: false
        // root.idleExits when this read started; see applyStatus().
        property int idleExits: 0
        onRunningChanged: if (running) idleExits = root.idleExits
        command: ["mpc", "status"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: root.applyStatus(statusCollector.text)
        }
        // The stream has ended by the time this fires (Quickshell emits
        // streamEnded before exited), so the re-run follows the apply.
        onExited: (code, status) => {
            if (code !== 0)
                root.setDisconnected();
            root.rerunIfDirty(statusProc);
        }
    }

    property Process currentTrackProc: Process {
        id: currentTrackProc
        property bool dirty: false
        // A missing tag expands to "", so fall back: a stream's name for its
        // artist, the file for an untagged title.
        command: ["mpc", "current", "-f", "[%artist%|%name%]\t[%title%|%file%]"]
        stdout: StdioCollector {
            id: currentCollector
            onStreamFinished: {
                const parts = currentCollector.text.replace(/\n$/, "").split("\t");
                root.artist = parts[0] || "";
                root.title = parts[1] || "";
            }
        }
        onExited: root.rerunIfDirty(currentTrackProc)
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
        // Not onExited: a process that fails to start (mpc missing) only
        // clears `running`. Refreshed at once, so a vanished mpd collapses
        // the module now rather than at the retry — counted as an exit
        // first, so that read is a fresh one (see applyStatus).
        onRunningChanged: if (!running) {
            root.idleExits++;
            root.failures++;
            restartTimer.interval = Math.min(root.retryInterval * 2 ** (root.failures - 1), root.maxRetryInterval);
            root.refresh();
            restartTimer.start();
        }
    }

    // idleloop exits when mpd isn't running or drops the connection. Retries
    // after 5s, doubling up to 30s while mpd stays down; a status read that
    // reaches mpd resets the backoff and restarts idleloop at once, so a drop
    // retries quickly again.
    readonly property int retryInterval: 5000
    readonly property int maxRetryInterval: 30000
    property int failures: 0
    property int idleExits: 0

    property Timer restartTimer: Timer {
        id: restartTimer
        onTriggered: {
            idleProc.running = true;
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
