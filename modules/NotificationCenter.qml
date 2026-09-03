import QtQuick
import Quickshell
import "../services"
import "../shared"
import "../shared/animations"

// Notification-center indicator + toggle. The actual daemon, popup stack,
// and control-center panel live in services/NotificationService.qml and
// shared/notifications/ (singleton + two top-level windows shared
// process-wide, instantiated once from shell.qml — the toast stack fixed to
// the main screen, the control-center panel following whichever screen's
// indicator was clicked, see `screen` below); this is just a thin
// per-output view, same shape as the old swaync-client indicator it
// replaces.
Item {
    id: root

    // Which output this bar instance (and thus this indicator) is on —
    // passed to NotificationService.toggleCenter() so the shared panel
    // opens on the screen actually clicked rather than always the main
    // screen. See Bar.qml's notificationsComponent.
    required property var screen

    readonly property int count: NotificationService.count
    readonly property string alt: NotificationService.iconState

    readonly property var icons: ({
        "notification": "󰂞",
        "none": "󰂚",
        "dnd-notification": "󰂛",
        "dnd-none": "󰂛"
    })
    readonly property var iconColors: ({
        "notification": "#F98AA4",
        "none": Theme.groupText,
        "dnd-notification": "#F98AA4",
        "dnd-none": "#9c9ca4"
    })

    readonly property real targetWidth: label.implicitWidth + 12
    implicitWidth: widthSpring.value
    implicitHeight: Theme.barHeight
    clip: true

    // FrameSpring, not Behavior/WidthSpring — see Submap.qml's FrameSpring
    // for why (Behavior-based SpringAnimation is throttled to Qt Quick's
    // shared ~60Hz GUI-thread clock regardless of the output's real refresh
    // rate).
    FrameSpring {
        id: widthSpring
        Component.onCompleted: snapTo(root.targetWidth)
    }

    onTargetWidthChanged: widthSpring.retarget(targetWidth)

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 0
    readonly property real iconSizeRatio: 0.9

    Text {
        renderType: Text.NativeRendering
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.iconVerticalOffset
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize(root.iconSizeRatio)
        color: root.iconColors[root.alt] || Theme.groupText
        text: root.icons[root.alt] || root.icons["none"]
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                NotificationService.toggleCenter(root.screen);
            else
                NotificationService.dnd = !NotificationService.dnd;
        }
    }
}
