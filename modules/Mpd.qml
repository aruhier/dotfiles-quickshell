import QtQuick
import Quickshell.Io

// Mirrors waybar's "mpd" module (talks to mpd via mpc since quickshell has
// no built-in mpd client; mpd is not exposed over mpris on this machine).
Item {
    id: root

    required property var theme

    // Named playbackState (not "state") because Item already has a built-in
    // "state" property for QtQuick's declarative state-machine feature —
    // shadowing it silently breaks bindings that read it.
    property string playbackState: "disconnected" // disconnected | stopped | playing | paused
    property string artist: ""
    property string title: ""

    readonly property int artistLen: 30
    readonly property int titleLen: 40

    visible: playbackState !== "disconnected"
    // Unconditional (not "visible ? content.implicitWidth + 12 : 0"): RowLayout
    // already excludes invisible children from layout, and gating this
    // binding on `visible` while it reads a child's implicitWidth triggers a
    // binding-evaluation bug that leaves `visible` stuck.
    implicitWidth: content.implicitWidth + 12
    implicitHeight: theme.barHeight

    function truncate(s, len) {
        return s.length > len ? s.substring(0, len - 1) + "…" : s;
    }

    readonly property bool hasTrack: playbackState === "playing" || playbackState === "paused"

    // Even box-centered against the label (equal geometric box-centers), the
    // icon glyph still reads as sitting above center: its ink is
    // concentrated in its upper portion (no descender use) while the label
    // has real visual mass down near the baseline, so the eye judges
    // "center" by ink-weighted mass, not box geometry. Nudges down to
    // compensate — tuned per module since different glyphs (and, here, a
    // variable-length label) sit differently within their own box; re-tune
    // by eye if it drifts.
    readonly property real iconVerticalOffset: 0

    // The play/pause/stop glyphs read visually smaller than other modules'
    // icons at the shared iconFontSize (small filled shapes vs. e.g. a full
    // bell/speaker outline) — bias this module's icon size up a bit. See
    // Theme.qml's iconSize().
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            renderType: Text.NativeRendering
            // Box-centered against the same Row as label, not baseline: with
            // two different pixelSizes, baseline anchoring pins both glyphs'
            // baseline to the same Y, but a much taller glyph's own visual
            // center then sits well above that shared line (ascent grows
            // with size, descent barely does), so the bigger icon ends up
            // looking like it floats above the label instead of centered
            // against it. Plain box-centering keeps both items' geometric
            // centers coincident regardless of size difference. Still nudged
            // down by iconVerticalOffset on top of that — see Theme.qml.
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.iconSize(root.iconSizeRatio)
            color: root.theme.groupText
            text: root.playbackState === "playing" ? "󰐊"
                : root.playbackState === "paused" ? "󰏤"
                : "󰓛"
        }

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasTrack
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
            color: root.theme.groupText
            text: root.hasTrack ? root.truncate(root.artist, root.artistLen) + " - " + root.truncate(root.title, root.titleLen) : ""
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
                root.playbackState = "disconnected";
        }
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
