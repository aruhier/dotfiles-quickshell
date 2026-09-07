pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.shared
import qs.shared.animations
import qs.shared.popup

// An icon per active privacy-sensitive capture: mic (any open audio-capture
// stream — ideally this would also require the stream to be RUNNING, but
// Quickshell's PwNode doesn't expose that) and screen-share.
//
// Not built on PwNodeLinkTracker(node: defaultAudioSource): a hardware capture
// device can carry idle/internal link groups with nothing actually recording,
// which showed the mic icon as active with no app capturing.
//
// No dedicated service: this isn't owned I/O, just a tracker plus a scan over
// the already-process-wide Pipewire.nodes — and this Item only exists on
// screens whose layout lists `privacy`, so the tracker runs only where the
// icon can show.
Item {
    id: root

    // Screen-capture streams need this tracker: an app's own
    // "Stream/Input/Video" node isn't one of the media classes Quickshell
    // hardcodes into PwNodeType, so `type` never reflects it — but
    // `properties`/`ready` populate fine once something tracks the node.
    property PwObjectTracker screenShareTracker: PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    readonly property string micGlyph: "󰍬"
    readonly property string screenGlyph: "󱒃"

    // A cast and a webcam are indistinguishable from the consumer side — both
    // are `Stream/Input/Video` named "firefox" with no application.name — so
    // the screen glyph keys off the portal's own Video/Source node, which
    // exists only for the life of a cast.
    //
    // Limit: with both running at once the camera consumer counts as screen
    // too. Separating them needs a PwNodeLinkTracker per consumer.
    readonly property bool screencastPortalActive: {
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            const props = node.properties || {};
            if (props["media.class"] !== "Video/Source")
                continue;
            if ((node.name || "").startsWith("xdg-desktop-portal"))
                return true;
        }
        return false;
    }

    // One row per app currently capturing, merging its mic and screen-share
    // nodes (a video-call app doing both is one row with two glyphs, not two
    // rows). Relies on screenShareTracker above already tracking every node:
    // an untracked node's `properties` never populates, whatever its media
    // class. See AGENT.md.
    readonly property var capturingApps: {
        const nodes = Pipewire.nodes.values;
        const apps = [];
        const indexByKey = {};
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            const props = node.properties || {};
            const mediaClass = props["media.class"];
            // Both off media.class: PwNodeType has no VideoStream member, so
            // the screen side could never use it. Exact compare, not a prefix
            // — a headset's always-present `Stream/Input/Audio/Internal` node
            // must not count as a mic.
            const isMic = mediaClass === "Stream/Input/Audio";
            const isScreen = mediaClass === "Stream/Input/Video" && root.screencastPortalActive;
            if (!isMic && !isScreen)
                continue;
            // One app's streams disagree on its name: Firefox is "Firefox" on
            // its mic stream and a lowercase "firefox", with no
            // application.name, on its video one. Fold case so they merge.
            const reported = props["application.name"] || "";
            const label = reported || node.name || "Unknown";
            const key = label.toLowerCase();
            let app = apps[indexByKey[key]];
            if (app === undefined) {
                indexByKey[key] = apps.length;
                app = {
                    name: label,
                    // Folded key, not the label: icon names are lowercase.
                    icon: props["application.icon-name"] || key,
                    mic: false,
                    screen: false
                };
                apps.push(app);
            } else if (reported) {
                app.name = reported;
            }
            if (isMic)
                app.mic = true;
            if (isScreen)
                app.screen = true;
        }
        return apps;
    }

    readonly property bool micActive: capturingApps.some(app => app.mic)
    readonly property bool screenShareActive: capturingApps.some(app => app.screen)

    // Plain bool, not read back through `visible` — see BarModule.qml's
    // `contentVisible` for why (Loader/visible deadlock).
    readonly property bool contentVisible: micActive || screenShareActive
    visible: contentVisible

    // Unconditional — see BarModule.qml for why gating width on the same
    // property as `visible` breaks visibility.
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight
    clip: true

    // Not BarModule: this is a per-capture-kind sub-icon inside the module,
    // not the module itself. It collapses to zero width on its own so that
    // mic-only and mic+screenshare both lay out right, while the module's own
    // width just follows the row.
    component PrivacyIcon: Item {
        id: icon
        required property bool active
        required property string glyph

        implicitWidth: widthSpring.value
        implicitHeight: Theme.barHeight
        clip: true

        FrameSpring {
            id: widthSpring
            to: icon.active ? label.implicitWidth + 8 : 0
        }

        Icon {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
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

    // LazyLoader, not Loader — see Clock.qml's popupLoader.
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

                StyledText {
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
                    // Gated on popup.visible, so delegates are destroyed while
                    // the popup is closed rather than staying resident — see
                    // Weather.qml's hourly Repeater.
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

                        StyledText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name
                            font.pixelSize: 12
                            color: Theme.textBright
                            elide: Text.ElideRight
                        }

                        Icon {
                            visible: appRow.modelData.mic
                            color: Theme.privacyActive
                            text: root.micGlyph
                        }

                        Icon {
                            visible: appRow.modelData.screen
                            color: Theme.privacyActive
                            text: root.screenGlyph
                        }
                    }
                }
            }
        }
    }
}
