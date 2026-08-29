import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// Approximates waybar's "privacy" module. Shows a mic icon while any
// application has an open audio-capture stream (waybar additionally checks
// the stream is in the RUNNING pipewire state, not just open; quickshell's
// PwNode doesn't expose per-node state, so this is the closest match).
//
// NOTE: screen-share detection (waybar's "screenshare" privacy item) isn't
// wired up here — quickshell has no simple node-graph signal for that, it
// would need an xdg-desktop-portal ScreenCast/DBus watcher.
//
// Deliberately NOT built on PwNodeLinkTracker(node: defaultAudioSource): a
// hardware capture device can carry idle/internal link groups (e.g. session
// -manager monitoring links) with no application actually recording, which
// made the mic icon show as active when nothing was capturing.
Item {
    id: root

    required property var theme

    readonly property bool micActive: {
        var nodes = Pipewire.nodes.values;
        for (var i = 0; i < nodes.length; i++) {
            if ((nodes[i].type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream)
                return true;
        }
        return false;
    }

    visible: micActive
    // Unconditional (not "micActive ? label.implicitWidth + 8 : 0"): see
    // Mpd.qml for why gating this on the same property used by `visible`
    // while reading a child's implicitWidth breaks visibility.
    implicitWidth: label.implicitWidth + 8
    implicitHeight: theme.barHeight

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: "#D14005"
        text: "󰍬"
    }
}
