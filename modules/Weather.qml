import QtQuick
import Quickshell
import Quickshell.Io
import "../shared"
import "../shared/pango.js" as Pango

// Mirrors waybar's "custom/weather" module: runs the existing get_weather.rb
// script (return-type json) and renders its Pango-formatted text/tooltip.
Item {
    id: root

    required property var theme

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/waybar/scripts/weather/get_weather.rb"

    property string rawText: ""
    property string rawTooltip: ""

    implicitWidth: rawText.length > 0 ? label.implicitWidth + 8 : 0
    implicitHeight: theme.barHeight

    Text {
        id: label
        anchors.centerIn: parent
        textFormat: Text.RichText
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.groupText
        text: Pango.pangoToRich(root.rawText)
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            nextProc.running = false;
            nextProc.running = true;
        }
    }

    Tooltip {
        anchorItem: root
        theme: root.theme
        show: hover.containsMouse
        maxWidth: 900
        text: Pango.pangoToRich(root.rawTooltip)
    }

    function applyOutput(text) {
        try {
            var obj = JSON.parse(text);
            root.rawText = obj.text || "";
            root.rawTooltip = obj.tooltip || "";
        } catch (e) {
            // leave previous values on parse failure
        }
    }

    Process {
        id: fetchProc
        command: [root.scriptPath]
        stdout: StdioCollector {
            id: fetchCollector
            onStreamFinished: root.applyOutput(fetchCollector.text)
        }
    }

    Process {
        id: nextProc
        command: [root.scriptPath, "--next"]
        onExited: {
            fetchProc.running = false;
            fetchProc.running = true;
        }
    }

    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            fetchProc.running = false;
            fetchProc.running = true;
        }
    }
}
