pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.shared
import qs.shared.popup

// System tray.
BarModule {
    id: root

    contentWidth: row.implicitWidth

    // One Tooltip for every icon, not one per delegate: a PopupWindow is a
    // real compositor surface and only one can show at a time. Two properties
    // because it needs the Item to anchor under and the SystemTrayItem to read
    // a label off — reaching the latter through the former would mean an
    // unverifiable read through an Item-typed handle.
    property Item hoveredIcon: null
    property SystemTrayItem hoveredItem: null

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 20

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayIcon
                required property var modelData

                Layout.preferredWidth: 14
                Layout.preferredHeight: 14

                IconImage {
                    anchors.fill: parent
                    source: trayIcon.modelData.icon
                    implicitSize: 14
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onContainsMouseChanged: {
                        if (containsMouse) {
                            root.hoveredIcon = trayIcon;
                            root.hoveredItem = trayIcon.modelData;
                        } else if (root.hoveredIcon === trayIcon) {
                            root.hoveredIcon = null;
                            root.hoveredItem = null;
                        }
                    }
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

                // An app quitting while its tooltip shows would otherwise
                // leave hoveredIcon pointing at a destroyed delegate.
                Component.onDestruction: {
                    if (root.hoveredIcon === trayIcon) {
                        root.hoveredIcon = null;
                        root.hoveredItem = null;
                    }
                }
            }
        }
    }

    // LazyLoader, not Loader: Tooltip is a PopupWindow, not an Item — see
    // Clock.qml's popupLoader. No close grace period here, so `active` can
    // mirror `show` instead of needing a teardown hook.
    LazyLoader {
        active: root.hoveredIcon !== null

        Tooltip {
            anchorItem: root.hoveredIcon || root
            show: root.hoveredIcon !== null
            // `title` first — some apps report garbage in tooltipTitle.
            text: root.hoveredItem ? (root.hoveredItem.title || root.hoveredItem.tooltipTitle || root.hoveredItem.id) : ""
        }
    }
}
