pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Caps/Num/Scroll lock state, read out of /sys/class/leds on demand.
//
// On demand and not watched, unlike BacklightService: an LED class attribute
// raises no inotify event, so there is nothing to subscribe to, and polling
// would cost at idle for a value that changes a few times a day. A Hyprland
// bindn on each lock key calls the `osd` IPC handler, which refreshes just
// before it shows the OSD. See AGENTS.md.
//
// One `cat` per read, and not FileView: FileView only loads synchronously
// once, so neither re-pointing one at each node nor reload()-ing a fixed one
// yields a fresh value. The glob is also what makes this indifferent to which
// keyboards are plugged in.
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

    // xkb *locks* one of these on key press but *unlocks* it on release, so
    // the second press of a pair doesn't reach the LED until the key comes
    // back up — measured at ~100ms here, against the ~12ms a bind takes to
    // reach this process. Binding on release instead doesn't help: Hyprland
    // never fires those. A lock key always toggles, so a read equal to the
    // value from before the press is provably early, and re-reading until it
    // changes needs no guess at how long the key was held.
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
    // is on — the same rule swayosd reads them by. No node at all (a keyboard
    // without the LED) reads as off, which is the best answer available, and
    // the budget above is what stops that waiting forever.
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
            // state apply() sets, and the two handlers' order against each
            // other isn't guaranteed.
            onStreamFinished: root.apply(readCollector.text)
        }
        onExited: root.flush()
    }
}
