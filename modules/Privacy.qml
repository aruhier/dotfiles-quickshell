import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../shared"

// Shows a mic icon while any app has an open audio-capture stream (ideally
// this would also require the stream to be RUNNING, not just open, but
// Quickshell's PwNode doesn't expose that state).
//
// Screen-share detection isn't implemented — would need an
// xdg-desktop-portal ScreenCast/DBus watcher.
//
// Not built on PwNodeLinkTracker(node: defaultAudioSource): a hardware
// capture device can carry idle/internal link groups with no app actually
// recording, which made the mic icon show active with nothing capturing.
Item {
    id: root

    readonly property bool micActive: {
        var nodes = Pipewire.nodes.values;
        for (var i = 0; i < nodes.length; i++) {
            if ((nodes[i].type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream)
                return true;
        }
        return false;
    }

    // Plain bool, not read back through `visible` — see Mpd.qml's
    // `contentVisible` for why (Loader/visible deadlock).
    readonly property bool contentVisible: micActive
    visible: contentVisible
    // Unconditional — see Mpd.qml for why gating width on the same property
    // as `visible` breaks visibility.
    implicitWidth: label.implicitWidth + 8
    implicitHeight: Theme.barHeight
    clip: true

    Behavior on implicitWidth {
        SpringAnimation {
            spring: Theme.springSpring
            damping: Theme.springDamping
            epsilon: Theme.springEpsilon
        }
    }

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 1
    readonly property real iconSizeRatio: 1.0

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.iconVerticalOffset
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize(root.iconSizeRatio)
        color: "#D14005"
        text: "󰍬"
    }
}
