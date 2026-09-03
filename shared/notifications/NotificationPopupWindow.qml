import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../../services"

// Floating notification-toast stack, top-right corner, sitting just under
// the bar — same vertical gap (module height + 4px) that
// ../popup/AnchoredPopupWindow.qml uses to drop its popups below a bar
// module. Screen-corner-anchored and independent of any bar module though,
// so a plain PanelWindow (same base Bar.qml itself uses) is the right fit
// here, not the module-anchored PopupWindow machinery in ../popup/ (that's
// built specifically to anchor below a *specific* bar module).
//
// Instantiated once from shell.qml — a single, shared window (not one per
// output), whose `screen` follows NotificationService.popupScreen: the
// output Hyprland had focused at the moment the notification arrived (set
// in NotificationService.qml's onNotification), falling back to the main
// screen before the first-ever notification. Same "single surface that
// follows the relevant output" shape as NotificationCenterPanel.qml's
// centerScreen, just captured at notification-arrival time instead of
// indicator-click time since a toast has no click of its own to anchor to.
PanelWindow {
    id: popupWindow

    anchors {
        top: true
        right: true
    }
    margins.top: Theme.barHeight + 4
    margins.right: 10

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Fully unmapped (zero footprint, no stray input-eating surface) while
    // there's nothing to show — same "don't pay for what isn't shown"
    // principle as Weather/Privacy/Tray's LazyLoaders.
    visible: NotificationService.popups.length > 0

    implicitWidth: NotificationTheme.notificationWidth
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: NotificationService.popups

            NotificationCard {
                id: card
                required property var modelData
                width: column.width
                wrapper: modelData
                floating: true

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }
        }
    }
}
