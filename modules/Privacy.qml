import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// Approximates waybar's "privacy" module. Shows a mic icon while any
// application is actively capturing audio from the default source.
//
// NOTE: screen-share detection (waybar's "screenshare" privacy item) isn't
// wired up here — quickshell has no simple node-graph signal for that, it
// would need an xdg-desktop-portal ScreenCast/DBus watcher. Audio-in is
// fully equivalent to waybar's behavior.
Item {
    id: root

    required property var theme

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micActive: linkTracker.linkGroups.length > 0

    PwObjectTracker {
        objects: root.source ? [root.source] : []
    }

    PwNodeLinkTracker {
        id: linkTracker
        node: root.source
    }

    visible: micActive
    implicitWidth: micActive ? label.implicitWidth + 8 : 0
    implicitHeight: theme.barHeight

    Text {
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: "#D14005"
        text: "󰍬"
    }
}
