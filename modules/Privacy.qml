import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import "../shared"
import "../shared/animations"
import "../shared/popup"

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

    readonly property string micGlyph: "󰍬"
    readonly property string screenGlyph: "󱒃"

    // One row per distinct app currently capturing, merging its mic and
    // screen-share nodes together (a video-call app doing both shows one
    // row with both glyphs, not two). Relies on screenShareTracker above
    // already tracking every node process-wide — an untracked node's
    // `properties` never populates regardless of media class (see AGENT.md),
    // so this reads the same tracked nodes rather than needing a tracker of
    // its own.
    readonly property var capturingApps: {
        var nodes = Pipewire.nodes.values;
        var apps = [];
        var indexByName = {};
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var isMic = (node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream;
            var props = node.properties || {};
            var isScreen = props["media.class"] === "Stream/Input/Video";
            if (!isMic && !isScreen)
                continue;
            var name = props["application.name"] || node.name || "Unknown";
            if (!(name in indexByName)) {
                indexByName[name] = apps.length;
                apps.push({
                    name: name,
                    icon: props["application.icon-name"] || name,
                    mic: false,
                    screen: false
                });
            }
            var app = apps[indexByName[name]];
            if (isMic)
                app.mic = true;
            if (isScreen)
                app.screen = true;
        }
        return apps;
    }
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

        readonly property real targetWidth: active ? label.implicitWidth + 8 : 0
        implicitWidth: widthSpring.value
        implicitHeight: Theme.barHeight
        clip: true

        // FrameSpring, not Behavior/WidthSpring — see Submap.qml's
        // FrameSpring for why (Behavior-based SpringAnimation is throttled
        // to Qt Quick's shared ~60Hz GUI-thread clock regardless of the
        // output's real refresh rate).
        FrameSpring {
            id: widthSpring
            Component.onCompleted: snapTo(icon.targetWidth)
        }

        onTargetWidthChanged: widthSpring.retarget(targetWidth)

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
            glyph: root.micGlyph
        }

        PrivacyIcon {
            active: root.screenShareActive
            glyph: root.screenGlyph
        }
    }

    HoverPopupArea {
        loader: popupLoader
    }

    // LazyLoader, not Loader: see Clock.qml's popupLoader for why (same
    // pattern — real GPU-backed window, destroyed once the close grace
    // period elapses instead of kept alive for the process lifetime).
    LazyLoader {
        id: popupLoader
        active: false

        HoverPopup {
            id: popup
            anchorItem: root

            visible: _open && root.contentVisible
            onVisibleChanged: {
                if (!visible)
                    popupLoader.active = false;
            }
            implicitWidth: 260
            implicitHeight: body.implicitHeight + 2 * padding

            ColumnLayout {
                id: body
                anchors.fill: parent
                spacing: 8

                Text {
                    renderType: Text.NativeRendering
                    Layout.fillWidth: true
                    text: "Currently capturing"
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.textBright
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.groupBg
                }

                Repeater {
                    // Gated on popup.visible, not just root.capturingApps —
                    // see Weather.qml's hourly Repeater for why (delegates
                    // destroyed while the popup is closed rather than
                    // staying resident for the process lifetime).
                    model: popup.visible ? root.capturingApps : []
                    delegate: RowLayout {
                        id: appRow
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 10

                        IconImage {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            source: Quickshell.iconPath(appRow.modelData.icon, "application-x-executable")
                        }

                        Text {
                            renderType: Text.NativeRendering
                            Layout.fillWidth: true
                            text: appRow.modelData.name
                            font.pixelSize: 12
                            color: Theme.textBright
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            visible: appRow.modelData.mic
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize()
                            color: Theme.privacyActive
                            text: root.micGlyph
                        }

                        Text {
                            renderType: Text.NativeRendering
                            visible: appRow.modelData.screen
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize()
                            color: Theme.privacyActive
                            text: root.screenGlyph
                        }
                    }
                }
            }
        }
    }
}
