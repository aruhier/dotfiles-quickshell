pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.shared
import qs.shared.animations
import qs.shared.popup
import qs.themes

// An icon per active capture — mic, screen share, camera — and a popup
// listing the apps behind them; a thin view over PrivacyService, which owns
// the Pipewire scan.
Item {
    id: root

    readonly property string micGlyph: "󰍬"
    readonly property string screenGlyph: "󱒃"
    readonly property string cameraGlyph: "󰖠"

    // Plain bool, not read back through `visible` — see BarModule.qml's
    // `contentVisible` for why (Loader/visible deadlock), and why it's not
    // mirrored onto `visible` here either.
    readonly property bool contentVisible: PrivacyService.anyActive

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
            active: PrivacyService.micActive
            glyph: root.micGlyph
        }

        PrivacyIcon {
            active: PrivacyService.screenActive
            glyph: root.screenGlyph
        }

        PrivacyIcon {
            active: PrivacyService.cameraActive
            glyph: root.cameraGlyph
        }
    }

    HoverPopupArea {
        loader: popupLoader
    }

    // LazyLoader, not Loader — see HoverPopupArea.qml.
    LazyLoader {
        id: popupLoader
        active: false

        HoverPopup {
            id: popup
            anchorItem: root

            visible: _open && root.contentVisible
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
                    model: popup.visible ? PrivacyService.capturingApps : []
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

                        Icon {
                            visible: appRow.modelData.camera
                            color: Theme.privacyActive
                            text: root.cameraGlyph
                        }
                    }
                }
            }
        }
    }
}
