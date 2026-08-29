import QtQuick
import Quickshell.Io

// Mirrors waybar's "mpd" module (talks to mpd via mpc since quickshell has
// no built-in mpd client; mpd is not exposed over mpris on this machine).
Item {
    id: root

    required property var theme

    property string state: "disconnected" // disconnected | stopped | playing | paused
    property string artist: ""
    property string title: ""

    readonly property int artistLen: 30
    readonly property int titleLen: 40

    visible: state !== "disconnected"
    implicitWidth: visible ? label.implicitWidth + 12 : 0
    implicitHeight: theme.barHeight

    function truncate(s, len) {
        return s.length > len ? s.substring(0, len - 1) + "…" : s;
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.groupText
        text: {
            var icon = root.state === "playing" ? "󰐊"
                : root.state === "paused" ? "󰏤"
                : "󰓛";
            if (root.state === "playing" || root.state === "paused")
                return icon + "  " + root.truncate(root.artist, root.artistLen) + " - " + root.truncate(root.title, root.titleLen);
            return icon;
        }
    }

    Process {
        id: statusProc
        command: ["mpc", "status"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: root.applyStatus(statusCollector.text)
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.state = "disconnected";
        }
    }

    function applyStatus(text) {
        if (!text) {
            root.state = "disconnected";
            return;
        }
        var lines = text.split("\n");
        if (lines[0].indexOf("volume:") !== 0) {
            root.state = "disconnected";
            return;
        }
        if (lines.length > 1 && lines[1].indexOf("[playing]") === 0) {
            root.state = "playing";
        } else if (lines.length > 1 && lines[1].indexOf("[paused]") === 0) {
            root.state = "paused";
        } else {
            root.state = "stopped";
            root.artist = "";
            root.title = "";
            return;
        }

        currentProc.running = false;
        currentProc.running = true;
    }

    Process {
        id: currentProc
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

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statusProc.running = false;
            statusProc.running = true;
        }
    }
}
