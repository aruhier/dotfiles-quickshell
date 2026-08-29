import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Mirrors waybar's "tray" module.
Item {
    id: root

    required property var theme

    implicitWidth: row.implicitWidth
    implicitHeight: theme.barHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayIcon
                required property var modelData

                Layout.preferredWidth: 16
                Layout.preferredHeight: 16

                IconImage {
                    anchors.fill: parent
                    source: trayIcon.modelData.icon
                    implicitSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            if (trayIcon.modelData.hasMenu && trayIcon.modelData.onlyMenu)
                                menuAnchor.open();
                            else
                                trayIcon.modelData.activate();
                        } else if (mouse.button === Qt.MiddleButton) {
                            trayIcon.modelData.secondaryActivate();
                        } else if (mouse.button === Qt.RightButton) {
                            if (trayIcon.modelData.hasMenu)
                                menuAnchor.open();
                        }
                    }
                }

                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayIcon.modelData.menu
                    anchor.item: trayIcon
                    anchor.edges: Edges.Bottom | Edges.Left
                    anchor.gravity: Edges.Bottom | Edges.Right
                }
            }
        }
    }
}
