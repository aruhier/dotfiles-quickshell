pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.shared

// MPD now-playing indicator (via mpc, since mpd isn't exposed over MPRIS
// here). Actual polling lives in services/MpdService.qml (singleton, one
// poll cycle for the whole process); this is just a thin view over that
// shared state.
BarModule {
    id: root

    // Named playbackState, not "state" — Item already has a built-in
    // "state" property and shadowing it silently breaks bindings.
    readonly property string playbackState: MpdService.playbackState
    readonly property string artist: MpdService.artist
    readonly property string title: MpdService.title

    readonly property int artistLen: 30
    readonly property int titleLen: 40

    contentVisible: playbackState !== "disconnected"
    contentWidth: content.implicitWidth

    function truncate(s, len) {
        return s.length > len ? s.substring(0, len - 1) + "…" : s;
    }

    readonly property bool hasTrack: playbackState === "playing" || playbackState === "paused"

    // Icon reads as sitting above center next to text (ink-weighted mass
    // vs. box geometry) — nudge down to compensate. Tuned per module.
    readonly property real iconVerticalOffset: 0
    // Play/pause/stop glyphs read smaller than other icons; bias up.
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Icon {
            // Box-centered against the Row, not baseline: with differing
            // pixelSizes, baseline anchoring would make the bigger icon
            // float above the label instead of looking centered against it.
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            text: root.playbackState === "playing" ? "󰐊" : root.playbackState === "paused" ? "󰏤" : "󰓛"
        }

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasTrack
            color: Theme.groupText
            text: root.hasTrack ? root.truncate(root.artist, root.artistLen) + " - " + root.truncate(root.title, root.titleLen) : ""
        }
    }
}
