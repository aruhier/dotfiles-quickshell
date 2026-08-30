pragma Singleton
import QtQuick
import Quickshell.Io

// Shared mpd state for the whole qs process — one persistent `mpc idleloop`
// subscription system-wide instead of one per monitor/Bar, and instead of
// polling `mpc status` on a fixed timer regardless of whether anything
// changed. `mpc idleloop <subsystem>` blocks on mpd's own `idle` protocol
// command and only prints a line when that subsystem actually changes
// (confirmed: a volume/mixer change while subscribed to just "player"
// produces no output at all) — refresh() then re-reads status/current on
// demand instead of every 2s regardless of whether anything happened.
// Mpd.qml (one instance per output) just reads these properties; only this
// singleton owns the Processes/Timer.
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
        // mpc status prints [state] on the last line before "volume:" only
        // when a song is loaded (line 0 is then the song title, not
        // "volume:..."), so find the state line by content rather than a
        // fixed index.
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

    // Long-lived subscription: one connection blocked in mpd's own `idle`
    // command instead of a busy poll. Restricted to "player" (play/pause/
    // stop/track-change) since that's the only subsystem this module
    // displays — a mixer (volume) or options change correctly produces no
    // output here and no wasted refresh.
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

    // mpc idleloop exits (rather than retrying itself) if mpd isn't running
    // or drops the connection — reconnect after a delay, same pattern as
    // services/SwayNCService.qml's subscription. Also re-syncs state on
    // reconnect in case something changed while disconnected.
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
