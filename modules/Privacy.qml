pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.shared
import qs.shared.animations
import qs.shared.popup
import qs.themes

// An icon per active privacy-sensitive capture: mic (any open audio-capture
// stream — Quickshell's PwNode can't tell whether it's actually RUNNING) and
// screen-share. Not built on PwNodeLinkTracker(node: defaultAudioSource): a
// capture device carries idle internal link groups, which showed the mic as
// active with nothing recording. No dedicated service — this is a scan over
// the process-wide Pipewire.nodes, and it only exists on screens that list
// `privacy`.
Item {
    id: root

    // Needed for screen capture: PwNodeType has no video-stream member, so
    // `type` never reflects one — but `properties` populates once tracked.
    property PwObjectTracker screenShareTracker: PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    readonly property string micGlyph: "󰍬"
    readonly property string screenGlyph: "󱒃"

    // A cast and a webcam look identical from the consumer side, so the screen
    // glyph keys off the portal's own Video/Source node, which exists only for
    // a cast's lifetime. Limit: with both running the camera counts as screen
    // too; separating them needs a PwNodeLinkTracker per consumer.
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

    // One row per capturing app, merging its mic and screen nodes, so a call
    // doing both is one row with two glyphs. Depends on screenShareTracker
    // above: an untracked node's `properties` never populates.
    readonly property var capturingApps: {
        const nodes = Pipewire.nodes.values;
        const apps = [];
        const indexByKey = {};
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            const props = node.properties || {};
            const mediaClass = props["media.class"];
            // Exact compare, not a prefix: a headset's always-present
            // `Stream/Input/Audio/Internal` node must not count as a mic.
            const isMic = mediaClass === "Stream/Input/Audio";
            const isScreen = mediaClass === "Stream/Input/Video" && root.screencastPortalActive;
            if (!isMic && !isScreen)
                continue;
            // One app's streams disagree on case (Firefox reports "Firefox"
            // on mic, "firefox" on video), so fold it to merge them.
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

    // Not BarModule — a sub-icon inside the module. It collapses to zero
    // width on its own, so the module's width just follows the row.
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
                    bold: true
                    color: Theme.textBright
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.groupBg
                }

                Repeater {
                    // Gated on popup.visible so delegates don't stay resident
                    // while closed — see Weather.qml's hourly Repeater.
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
