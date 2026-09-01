import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../shared"
import "../shared/animations"

// Shows an icon per active privacy-sensitive capture: mic (any open
// audio-capture stream — ideally this would also require the stream to be
// RUNNING, not just open, but Quickshell's PwNode doesn't expose that state)
// and screen-share.
//
// Not built on PwNodeLinkTracker(node: defaultAudioSource): a hardware
// capture device can carry idle/internal link groups with no app actually
// recording, which made the mic icon show active with nothing capturing.
//
// screenShareActive needs its own PwObjectTracker: a capturing app's own
// "Stream/Input/Video" client stream isn't one of the media classes
// Quickshell's node.cpp hardcodes into PwNodeType, so `type` never reflects
// it — but `properties`/`ready` populate fine once something tracks the
// node (same as any other Pipewire node Quickshell isn't tracking by
// default). No dedicated service for this: it's not owned I/O, just a
// PwObjectTracker + a scan over the already-process-wide Pipewire.nodes —
// same shape as micActive above, and this Item only exists at all on
// screens whose layout lists `privacy`, so the tracker only runs where the
// icon can actually show.
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

    property PwObjectTracker screenShareTracker: PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    readonly property bool screenShareActive: {
        var nodes = Pipewire.nodes.values;
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (node.properties && node.properties["media.class"] === "Stream/Input/Video")
                return true;
        }
        return false;
    }

    // Plain bool, not read back through `visible` — see Mpd.qml's
    // `contentVisible` for why (Loader/visible deadlock).
    readonly property bool contentVisible: micActive || screenShareActive
    visible: contentVisible
    // Unconditional — see Mpd.qml for why gating width on the same property
    // as `visible` breaks visibility.
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight
    clip: true

    // One icon per active capture kind, each collapsing to 0 width on its
    // own so e.g. mic-only and mic+screenshare both look right.
    component PrivacyIcon: Item {
        id: icon
        required property bool active
        required property string glyph

        implicitWidth: active ? label.implicitWidth + 8 : 0
        implicitHeight: Theme.barHeight
        clip: true

        Behavior on implicitWidth {
            WidthSpring {}
        }

        Text {
            renderType: Text.NativeRendering
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize()
            color: Theme.privacyActive
            text: icon.glyph
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 0

        PrivacyIcon {
            active: root.micActive
            glyph: "󰍬"
        }

        PrivacyIcon {
            active: root.screenShareActive
            glyph: "󱒃"
        }
    }
}
