import QtQuick
import "../services"

// Mirrors waybar's "mpd" module (talks to mpd via mpc since quickshell has
// no built-in mpd client; mpd is not exposed over mpris on this machine).
// The actual `mpc` polling lives in services/MpdService.qml (a singleton) so
// there's exactly one poll cycle for the whole qs process, not one per
// monitor/Bar — this is just a thin view over that shared state.
Item {
    id: root

    required property var theme

    // Named playbackState (not "state") because Item already has a built-in
    // "state" property for QtQuick's declarative state-machine feature —
    // shadowing it silently breaks bindings that read it.
    readonly property string playbackState: MpdService.playbackState
    readonly property string artist: MpdService.artist
    readonly property string title: MpdService.title

    readonly property int artistLen: 30
    readonly property int titleLen: 40

    visible: playbackState !== "disconnected"
    // Unconditional (not "visible ? content.implicitWidth + 12 : 0"): RowLayout
    // already excludes invisible children from layout, and gating this
    // binding on `visible` while it reads a child's implicitWidth triggers a
    // binding-evaluation bug that leaves `visible` stuck.
    implicitWidth: content.implicitWidth + 12
    implicitHeight: theme.barHeight
    // See Theme.qml's resizeDuration: content (already resized) would
    // otherwise poke out past this Item's still-catching-up bounds while
    // growing.
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
}
