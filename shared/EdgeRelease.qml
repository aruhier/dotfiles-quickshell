pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Tells the Hyprland config's `bar_released` which workspace, if any, a bar
// has given its space to, so a lone tiled window there loses gaps, border and
// rounding. One call in flight at a time, always the latest state. See
// notes/autohide.md.
Scope {
    id: root

    required property string output
    // Empty while the bar reserves its space.
    property string workspaceName: ""

    // A JSON string is a valid Lua string literal.
    readonly property string call: `bar_released(${JSON.stringify(root.output)}, ${root.workspaceName ? JSON.stringify(root.workspaceName) : "nil"})`
    property string sentCall: ""
    onCallChanged: Qt.callLater(root.send)
    // Also undoes a release left behind by a shell that died hidden.
    Component.onCompleted: root.send()

    function send() {
        if (process.running || root.sentCall === root.call)
            return;
        root.sentCall = root.call;
        process.command = ["hyprctl", "eval", root.sentCall];
        process.running = true;
    }

    Process {
        id: process
        stdout: StdioCollector {
            id: reply
        }
        onExited: code => {
            if (code !== 0)
                console.warn(`EdgeRelease: ${root.sentCall} failed: ${reply.text.trim()}`);
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
