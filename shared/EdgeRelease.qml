pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Tells the Hyprland config's `quickshell.bar_autohide` which workspace, if
// any, a bar has given its space to, so a lone tiled window there loses gaps,
// border and rounding. One call in flight at a time, always the latest state.
// See notes/autohide.md.
Scope {
    id: root

    required property string output
    // Empty while the bar reserves its space.
    property string workspaceName: ""

    // A JSON string is a valid Lua string literal.
    readonly property string call: `quickshell.bar_autohide(${JSON.stringify(root.output)}, ${root.workspaceName ? JSON.stringify(root.workspaceName) : "nil"})`
    property string sentCall: ""
    onCallChanged: Qt.callLater(root.send)
    // Also undoes a release left behind by a shell that died hidden. Deferred
    // like the above, so it coalesces with the first workspace the Bar
    // settles on instead of sending nil and then that.
    Component.onCompleted: Qt.callLater(root.send)

    function send() {
        if (process.running || root.sentCall === root.call)
            return;
        root.sentCall = root.call;
        root.exitCode = -1;
        process.command = ["hyprctl", "eval", root.sentCall];
        process.running = true;
    }

    Process {
        id: process
        stdout: StdioCollector {
            id: reply
        }
        onExited: code => {
            root.exitCode = code;
            if (code !== 0)
                console.warn(`EdgeRelease: ${root.sentCall} failed: ${reply.text.trim()}`);
        }
        // Not onExited: a hyprctl that fails to start only clears `running`
        // (Quickshell warns itself). `exited`, when it comes, fires first.
        onRunningChanged: {
            if (running)
                return;
            if (root.exitCode !== 0) {
                // Once per failure run, not in a loop: a missing Lua
                // function fails every time.
                if (!root.retried) {
                    root.retried = true;
                    retryTimer.start();
                }
            } else {
                root.retried = false;
            }
            root.send();
        }
    }
    // -1 until `exited` reports: a start that failed.
    property int exitCode: -1

    // `sentCall` is set before the exit code is known, so a transient failure
    // (Hyprland busy, a socket timeout) would otherwise never be re-sent.
    property bool retried: false
    Timer {
        id: retryTimer
        interval: 2000
        onTriggered: {
            root.sentCall = "";
            root.send();
        }
    }

    // A config reload drops rules set at runtime.
    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded") {
                root.sentCall = "";
                root.send();
            }
        }
    }
}
