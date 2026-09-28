pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Caps/Num/Scroll lock state, read out of /sys/class/leds on demand — when a
// lock key's bind calls the `osd` IPC handler. Not watched (LED attributes
// raise no inotify event) and a `cat` per read, not FileView (it won't
// reload a changed sysfs node). See notes/osd.md.
QtObject {
    id: root

    property bool capsLock: false
    property bool numLock: false
    property bool scrollLock: false

    readonly property var keys: ["capslock", "numlock", "scrolllock"]

    // Emitted once a refresh() has settled on an answer, with its key. Not
    // emitted for the start-up priming reads.
    signal refreshed(string key)

    function state(key) {
        return key === "capslock" ? capsLock : key === "numlock" ? numLock : scrollLock;
    }

    // xkb unlocks on key *release*, so a read can land before the LED moves.
    // A lock key always toggles: a read equal to the value from before the
    // press is early, and is re-read until it changes or the budget runs out.
    // See notes/osd.md, "xkb unlocks a lock key on release".
    readonly property int settleInterval: 30
    readonly property int settleBudget: 1000

    // Keys read at least once, so `baseline` below means something. Primed at
    // start-up, since the first press of a session would otherwise have no
    // value to be early against.
    property var seen: ({})

    // Queued {key, silent} reads: exec() isn't a queue, and priming enqueues
    // all three at once.
    property var queue: []
    property string activeKey: ""
    property bool activeSilent: false
    property string baseline: ""
    property double deadline: 0

    Component.onCompleted: prime()

    function prime() {
        for (const key of keys)
            queue.push({
                "key": key,
                "silent": true
            });
        flush();
    }

    function refresh(key) {
        // Also what keeps the key out of the shell command below: it can only
        // ever be one of three literals.
        if (keys.indexOf(key) === -1)
            return;
        queue.push({
            "key": key,
            "silent": false
        });
        flush();
    }

    function flush() {
        if (queue.length === 0 || readProc.running || settleTimer.running)
            return;
        const next = queue.shift();
        activeKey = next.key;
        activeSilent = next.silent;
        // Empty when there's nothing to be early against, which makes the
        // first read final.
        baseline = !activeSilent && seen[activeKey] ? (state(activeKey) ? "1" : "0") : "";
        deadline = Date.now() + settleBudget;
        read();
    }

    function read() {
        readProc.exec(["sh", "-c", "cat /sys/class/leds/*::" + activeKey + "/brightness"]);
    }

    // xkb lights every attached keyboard's node, so any one lit means the lock
    // is on. No node at all (a keyboard without the LED) reads as off, and the
    // budget above is what stops that waiting forever.
    function apply(text) {
        const value = text.split("\n").indexOf("1") !== -1 ? "1" : "0";
        if (value === baseline && Date.now() < deadline) {
            settleTimer.restart();
            return;
        }

        seen[activeKey] = true;
        const on = value === "1";
        if (activeKey === "capslock")
            capsLock = on;
        else if (activeKey === "numlock")
            numLock = on;
        else if (activeKey === "scrolllock")
            scrollLock = on;

        if (!activeSilent)
            refreshed(activeKey);
    }

    property Timer settleTimer: Timer {
        id: settleTimer
        interval: root.settleInterval
        onTriggered: root.read()
    }

    property Process readProc: Process {
        id: readProc
        stdout: StdioCollector {
            id: readCollector
            // Applied here rather than from onExited, and refreshed() is
            // emitted from inside it: whoever shows an OSD for this reads the
            // state apply() sets. (Quickshell does emit streamFinished before
            // exited; keeping the apply with its data just doesn't lean on it.)
            onStreamFinished: root.apply(readCollector.text)
        }
        onExited: root.flush()
    }
}
