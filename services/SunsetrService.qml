pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Shared sunsetr state, read straight off its event socket: one JSON object
// per line, the current state sent on connect, then every change. Nothing is
// forked or polled, running or stopped. See notes/sunsetr.md.
QtObject {
    id: root

    // `sunsetr` is on PATH. The module hides without it, but stays while the
    // daemon is merely stopped, so it can be started again from the bar.
    property bool installed: false
    readonly property bool running: events.connected

    // day | sunset | night | sunrise | static; "" while stopped.
    property string period: ""
    property string preset: "default"
    property bool transitioning: false
    // 0..1 through a sunset or sunrise.
    property real progress: 0
    property int temperature: 0
    property real gamma: 100
    property int targetTemperature: 0
    // Date of the next period change, null in static mode.
    property var nextPeriod: null

    // When a suspend brings sunsetr back, null without one. Read off the
    // systemd timer, so it survives a shell reload.
    property var resumeAt: null
    readonly property bool suspended: !running && resumeAt !== null
    // Set by suspend() until its read-back lands: that read can beat the
    // socket's close, and would otherwise take the new timer for a leftover.
    property bool ownSuspend: false

    // Off the active configuration, refreshed when it changes.
    property string mode: ""
    property real latitude: NaN
    property real longitude: NaN

    readonly property var nextPeriods: ({
        day: "sunset",
        sunset: "night",
        night: "sunrise",
        sunrise: "day"
    })
    readonly property string nextPeriodName: nextPeriods[period] ?? ""

    readonly property string serviceUnit: "sunsetr.service"
    // The transient timer (and service) a suspend creates.
    readonly property string resumeUnit: "sunsetr-resume"

    // Stopping resets the screen to neutral; starting goes through systemd
    // so the daemon outlives the shell, and cancels a pending resume.
    // `sunsetr stop` rather than systemctl, so an instance started outside
    // systemd stops too.
    function toggle() {
        if (!root.installed || ctlProc.running)
            return;
        if (root.running) {
            ctlProc.exec(["sunsetr", "stop"]);
        } else {
            root.cancelResume();
            ctlProc.exec(["systemctl", "--user", "start", root.serviceUnit]);
        }
    }

    // Off now, back on in `minutes`. A systemd timer rather than one here, so
    // the resume happens with the shell reloaded or gone. An absolute time,
    // not --on-active: that clock stops while the machine sleeps, and its due
    // time can't be read back. In UTC, so a DST fall-back hour can't make it
    // ambiguous. --collect, or a resume whose start failed stays loaded and
    // its name blocks every later suspend. A previous timer is replaced.
    function suspend(minutes) {
        if (!root.installed || ctlProc.running)
            return;
        const at = new Date(Date.now() + minutes * 60000);
        root.resumeAt = at;
        root.ownSuspend = true;
        ctlProc.exec(["sh", "-c",
            "systemctl --user stop \"$2.timer\" 2>/dev/null; "
            + "systemd-run --user --quiet --collect --unit=\"$2\" --on-calendar=\"$1\" "
            + "--timer-property=AccuracySec=1s systemctl --user start \"$3\" || exit 1; "
            + "sunsetr stop >/dev/null 2>&1; exit 0",
            "sh", at.toISOString().slice(0, 19).replace("T", " ") + " UTC", root.resumeUnit, root.serviceUnit]);
    }

    // Never restarts a read in flight; a request during one re-runs it on
    // exit, so the last state always lands. As in MpdService.
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

    // Everything the socket sets, so the next connect can't show the last
    // session's values before its first state lands.
    function reset() {
        root.period = "";
        root.preset = "default";
        root.transitioning = false;
        root.progress = 0;
        root.temperature = 0;
        root.gamma = 100;
        root.targetTemperature = 0;
        root.nextPeriod = null;
    }

    // next_period carries nanoseconds, which Date() doesn't parse.
    function parseDate(text) {
        if (!text)
            return null;
        const date = new Date(text.replace(/(\.\d{3})\d+/, "$1"));
        return isNaN(date.getTime()) ? null : date;
    }

    function apply(line) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            console.warn("SunsetrService: unparsable event:", line);
            return;
        }
        switch (event.event_type) {
        case "state_applied":
            root.period = event.period ?? "";
            root.preset = event.active_preset ?? "default";
            root.transitioning = event.state === "transitioning";
            root.progress = event.progress ?? 0;
            root.temperature = event.current_temp ?? 0;
            root.gamma = event.current_gamma ?? 100;
            root.targetTemperature = event.target_temp ?? root.temperature;
            root.nextPeriod = root.parseDate(event.next_period);
            break;
        case "period_changed":
            root.period = event.to_period ?? root.period;
            break;
        case "preset_changed":
            root.preset = event.to_preset ?? root.preset;
            root.rerun(configProc);
            break;
        case "config_changed":
            root.rerun(configProc);
            break;
        }
    }

    property Socket events: Socket {
        id: events
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/sunsetr-events.sock"
        // Connected from onLockPresentChanged, once the folder scan lands.
        connected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.apply(line)
        }
        onConnectedChanged: {
            if (connected) {
                retry.interval = retry.minInterval;
                root.rerun(configProc);
                // Back before its resume (started by hand, or the timer just
                // fired): the suspend is over either way.
                if (root.resumeAt !== null)
                    root.cancelResume();
            } else {
                root.reset();
            }
        }
    }

    // A clean stop removes the lock, so a stopped daemon costs no connect
    // attempts (each failed one logs a warning). A failed connect raises no
    // change on `connected`, hence the timer while the lock is up. It backs
    // off for a lock a killed instance left, but only to 10s: a new instance
    // likely reuses that file, so its arrival raises no change here.
    readonly property bool lockPresent: lockWatch.count > 0
    onLockPresentChanged: if (lockPresent) {
        retry.interval = retry.minInterval;
        events.connected = true;
    }

    property FolderListModel lockWatch: FolderListModel {
        id: lockWatch
        folder: "file://" + Quickshell.env("XDG_RUNTIME_DIR")
        nameFilters: ["sunsetr.lock"]
        showDirs: false
        showDotAndDotDot: false
    }

    property Timer retry: Timer {
        id: retry
        readonly property int minInterval: 1000
        readonly property int maxInterval: 10000
        interval: minInterval
        repeat: true
        running: root.lockPresent && !events.connected
        onTriggered: {
            events.connected = true;
            interval = Math.min(interval * 2, maxInterval);
        }
    }

    property Process configProc: Process {
        id: configProc
        property bool dirty: false
        command: ["sunsetr", "get", "--json", "transition_mode", "latitude", "longitude"]
        stdout: StdioCollector {
            id: configCollector
            onStreamFinished: {
                let config;
                try {
                    config = JSON.parse(configCollector.text);
                } catch (e) {
                    console.warn("SunsetrService: unparsable config:", configCollector.text);
                    return;
                }
                root.mode = config.transition_mode ?? "";
                root.latitude = parseFloat(config.latitude);
                root.longitude = parseFloat(config.longitude);
            }
        }
        onExited: root.rerunIfDirty(configProc)
    }

    function cancelResume() {
        root.resumeAt = null;
        Quickshell.execDetached(["systemctl", "--user", "stop", root.resumeUnit + ".timer"]);
    }

    // Every start, stop and suspend: one at a time, so a suspend's stop can't
    // race a toggle's start.
    property Process ctlProc: Process {
        id: ctlProc
        // On `running` falling, not onExited: a command that fails to start
        // only clears `running`. After a start, connect now rather than at the
        // next retry; after a stop the lock is gone and there's nothing to
        // reach. The resume time is re-read, as a failed suspend sets none.
        onRunningChanged: if (!running) {
            if (root.lockPresent && !events.connected)
                events.connected = true;
            root.rerun(resumeProc);
        }
    }

    // A timer that fired without bringing sunsetr back (its start failed, or
    // the unit's condition didn't hold) would leave "Suspended until" past
    // due: re-read once the time has gone. Checked every 30s rather than
    // aimed at the time, since a Timer's clock stops during sleep.
    property Timer resumeCheck: Timer {
        interval: 30000
        repeat: true
        running: root.suspended
        onTriggered: if (Date.now() >= root.resumeAt.getTime() + 5000)
            root.rerun(resumeProc)
    }

    // "@<unix seconds>", or empty with no timer.
    property Process resumeProc: Process {
        id: resumeProc
        property bool dirty: false
        command: ["systemctl", "--user", "show", root.resumeUnit + ".timer", "-p", "NextElapseUSecRealtime", "--value", "--timestamp=unix"]
        running: true
        stdout: StdioCollector {
            id: resumeCollector
            onStreamFinished: {
                const match = resumeCollector.text.trim().match(/^@(\d+)$/);
                const own = root.ownSuspend;
                root.ownSuspend = false;
                if (!match) {
                    root.resumeAt = null;
                } else if (root.running && !own) {
                    // A leftover from a suspend ended by hand while the shell
                    // was away.
                    root.cancelResume();
                } else {
                    root.resumeAt = new Date(parseInt(match[1]) * 1000);
                }
            }
        }
        onExited: root.rerunIfDirty(resumeProc)
    }

    property Process whichProc: Process {
        command: ["sh", "-c", "command -v sunsetr"]
        running: true
        onExited: (code) => root.installed = code === 0
    }
}
