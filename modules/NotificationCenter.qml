pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.shared
import qs.shared.popup
import qs.themes

// Notification-center indicator and toggle. The daemon, popup stack and
// control-center panel live in NotificationService and shared/notifications/;
// this is just the per-output view. Left click toggles the panel, right click
// toggles do-not-disturb.
BarModule {
    id: root

    // Which output this bar (and so this indicator) is on — passed to
    // toggleCenter() so the shared panel opens on the screen actually clicked.
    // See Bar.qml's notificationsComponent.
    required property var screen

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

    contentWidth: label.implicitWidth

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 0
    readonly property real iconSizeRatio: 0.9

    Icon {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.iconVerticalOffset
        sizeRatio: root.iconSizeRatio
        color: root.iconColors[root.alt] || Theme.groupText
        text: root.icons[root.alt] || root.icons["none"]
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                NotificationService.toggleCenter(root.screen);
            else
                NotificationService.dnd = !NotificationService.dnd;
        }
        hoverEnabled: true
    }

    LazyLoader {
        active: hover.containsMouse

        Tooltip {
            anchorItem: root
            show: hover.containsMouse
            text: NotificationService.notifications.length + " notifications"
        }
    }
}
