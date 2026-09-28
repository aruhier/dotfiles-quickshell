pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// The active Hyprland submap. Quickshell exposes submaps only as `submap>>`
// events, so a bar built mid-submap (a reload, a hotplug) would show nothing
// until the next change: the state is seeded from `hyprctl submap` at start
// and after a config reload, then follows the events.
QtObject {
    id: root

    property bool active: false
    // Kept after the submap ends, so a label still has text while it
    // collapses. Set before `active`, so a module sizes off the new name.
    property string lastName: ""

    // An event newer than a seed in flight wins over its answer.
    property bool eventSinceSeed: false

    function apply(name) {
        if (name !== "")
            root.lastName = name;
        root.active = name !== "";
    }

    function seed() {
        root.eventSinceSeed = false;
        seedProc.running = true;
    }

    property Process seedProc: Process {
        id: seedProc
        command: ["hyprctl", "-j", "submap"]
        stdout: StdioCollector {
            id: seedReply
            onStreamFinished: {
                if (root.eventSinceSeed)
                    return;
                try {
                    const name = JSON.parse(seedReply.text);
                    // Reported as "default" when none is active, where the
                    // event says "".
                    root.apply(name === "default" ? "" : String(name));
                } catch (e) {
                    console.warn(`SubmapService: unreadable hyprctl reply: ${seedReply.text.trim()}`);
                }
            }
        }
    }

    property Connections events: Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "submap") {
                root.eventSinceSeed = true;
                root.apply(event.data);
            } else if (event.name === "configreloaded") {
                // A reload can drop or reset submaps without an event.
                root.seed();
            }
        }
    }

    Component.onCompleted: seed()
}
