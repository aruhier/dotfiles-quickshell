pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.shared
import qs.themes

// MPD now-playing indicator — a thin view over MpdService, which owns the
// mpc subscription.
BarModule {
    id: root

    // Named playbackState, not "state": Item already has a built-in `state`
    // property, and shadowing it silently breaks bindings.
    readonly property string playbackState: MpdService.playbackState
    readonly property string artist: MpdService.artist
    readonly property string title: MpdService.title

    readonly property int artistLen: 30
    readonly property int titleLen: 40

    contentVisible: playbackState !== "disconnected"
    contentWidth: content.implicitWidth

    // By code point, so a cut never splits a surrogate pair (emoji, CJK
    // extension B) into a tofu box.
    function truncate(s, len) {
        const chars = Array.from(s);
        return chars.length > len ? chars.slice(0, len - 1).join("") + "…" : s;
    }

    readonly property string label: [truncate(artist, artistLen), truncate(title, titleLen)].filter(Boolean).join(" - ")

    readonly property bool hasTrack: playbackState === "playing" || playbackState === "paused"

    // Icon vertical nudge / size bias — see Icon.qml. These glyphs sit
    // centred already; play/pause/stop read smaller than others, so bias up.
    readonly property real iconVerticalOffset: 0
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.iconLabelSpacing

        Icon {
            // Box-centered against the Row, not baseline: with differing
            // pixelSizes, baseline anchoring floats the bigger icon above the
            // label instead of looking centered against it.
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            color: root.textColor
            text: root.playbackState === "playing" ? "󰐊" : root.playbackState === "paused" ? "󰏤" : "󰓛"
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasTrack && root.label !== ""
            color: root.textColor
            text: root.label
        }
    }
}
