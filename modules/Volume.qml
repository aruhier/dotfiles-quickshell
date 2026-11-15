pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.shared
import qs.shared.animations
import qs.shared.popup
import qs.themes

// Volume indicator, a thin view over AudioService, which owns the default
// sink and the writes. A hover popup names the default sink and source, each
// with its level.
BarModule {
    id: root

    readonly property bool muted: AudioService.muted
    readonly property int pct: AudioService.pct

    // One wheel notch, in percentage points.
    readonly property int step: 5

    // Hidden with no default sink, rather than a low-volume glyph at 0%.
    contentVisible: AudioService.ready
    contentWidth: content.implicitWidth

    // Icon vertical nudge / size bias — see Icon.qml.
    readonly property real iconVerticalOffset: 0.5
    readonly property real iconSizeRatio: 1.1

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.iconLabelSpacing

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            color: root.textColor
            text: AudioService.icon
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            // Muted replaces the whole format: icon only, no percent.
            visible: !root.muted
            color: root.textColor
            text: root.pct + "%"
        }
    }

    // Hover only: takes no button, so clicks and the wheel reach the wheel
    // area on top, and the popup stays up to show the wheel's steps.
    HoverPopupArea {
        id: hoverArea
        loader: popupLoader
        acceptedButtons: Qt.NoButton
    }

    NotchWheelArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            hoverArea.cancel();
            Quickshell.execDetached(["pavucontrol"]);
        }
        onStepped: (notches) => AudioService.bumpPct(notches * root.step)
    }

    // One default device: the OSD's glyph for its direction, centred on the
    // two lines, then its name and value over a level track like the OSD's.
    component DeviceRow: GridLayout {
        id: row
        required property PwNode node
        required property string glyph

        readonly property bool ready: AudioService.nodeReady(node)
        readonly property bool muted: ready && node.audio.muted
        readonly property real volume: ready ? node.audio.volume : 0

        visible: !!node
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        rowSpacing: 5

        Icon {
            Layout.rowSpan: 2
            Layout.alignment: Qt.AlignVCenter
            color: Theme.accent
            text: row.glyph
        }

        StyledText {
            Layout.fillWidth: true
            text: row.node ? AudioService.label(row.node) : ""
            color: Theme.text
            elide: Text.ElideRight
        }

        // A fixed slot, not the label's own width: the name would otherwise
        // shift as the value goes 9% -> 10% -> 100%.
        StyledText {
            id: value
            Layout.preferredWidth: widest.width
            horizontalAlignment: Text.AlignRight
            text: !row.ready ? "" : row.muted ? "Muted" : Math.round(row.volume * 100) + "%"
            color: Theme.textBright

            TextMetrics {
                id: widest
                font: value.font
                text: "Muted"
            }
        }

        Rectangle {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            radius: height / 2
            color: Theme.groupBg

            Rectangle {
                // Never narrower than one cap, as in the OSD: an empty fill
                // reads as a broken track.
                width: Math.max(parent.height, parent.width * Ramp.clamp01(row.volume))
                height: parent.height
                radius: parent.radius
                // Muted still has a level, just not an audible one.
                color: row.muted ? Theme.text : Theme.accent
            }
        }
    }

    // LazyLoader, not Loader — see HoverPopupArea.qml.
    LazyLoader {
        id: popupLoader
        active: false

        HoverPopup {
            id: popup
            anchorItem: root

            visible: popup.isShown && root.contentVisible
            wantedWidth: 260
            wantedHeight: body.implicitHeight + 2 * padding

            // The anchor is placed only on a popup resize or move, and this is
            // the one module whose width changes under an open popup (the
            // wheel, mute): re-centre on it.
            Connections {
                target: root
                function onWidthChanged(): void {
                    popup.anchor.updateAnchor();
                }
            }

            // The source's volume binds only while tracked. AudioService
            // tracks the sink alone, and PrivacyService's all-node tracker
            // exists only with a Privacy module, so this covers the rest.
            PwObjectTracker {
                objects: AudioService.source ? [AudioService.source] : []
            }

            ColumnLayout {
                id: body
                anchors.fill: parent
                spacing: 12

                DeviceRow {
                    node: AudioService.sink
                    glyph: AudioService.sinkGlyph
                }

                DeviceRow {
                    node: AudioService.source
                    glyph: AudioService.sourceGlyph
                }
            }
        }
    }
}
