import QtQuick
import "../services"

// Mirrors waybar's "mpd" module (via mpc, since quickshell has no built-in
// mpd client and mpd isn't exposed over mpris here). Actual polling lives
// in services/MpdService.qml (singleton, one poll cycle for the whole
// process); this is just a thin view over that shared state.
Item {
    id: root

    required property var theme

    // Named playbackState, not "state" — Item already has a built-in
    // "state" property and shadowing it silently breaks bindings.
    readonly property string playbackState: MpdService.playbackState
    readonly property string artist: MpdService.artist
    readonly property string title: MpdService.title

    readonly property int artistLen: 30
    readonly property int titleLen: 40

    visible: playbackState !== "disconnected"
    // Unconditional, not gated on `visible`: reading a child's
    // implicitWidth in a binding also gated on `visible` leaves `visible`
    // stuck due to a QML binding-evaluation quirk.
    implicitWidth: content.implicitWidth + 12
    implicitHeight: theme.barHeight
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
        }
    }

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

        Text {
            renderType: Text.NativeRendering
            // Box-centered against the Row, not baseline: with differing
            // pixelSizes, baseline anchoring would make the bigger icon
            // float above the label instead of looking centered against it.
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
}
