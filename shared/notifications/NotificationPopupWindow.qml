import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Floating notification-toast stack, top-right corner — swaync's
// positionX/Y: right/top. Screen-corner-anchored and independent of any bar
// module, so a plain PanelWindow (same base Bar.qml itself uses) is the
// right fit here, not the module-anchored PopupWindow machinery in
// ../popup/ (that's built specifically to anchor below a bar module).
//
// Instantiated once from shell.qml, bound to the main screen only — mirrors
// the existing convention that the one shared, real UI surface for an
// "expensive" subsystem (Tray/Privacy/Weather) lives on the main screen,
// even though the lightweight bar indicator itself appears on every output.
PanelWindow {
    id: popupWindow

    anchors {
        top: true
        right: true
    }
    margins.top: 10
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
