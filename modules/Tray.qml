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

    // One Tooltip shared across every tray icon rather than one per delegate:
    // a PopupWindow is a real compositor surface, and only one can be shown at
    // a time anyway since the MouseAreas don't overlap.
    //
    // Two properties, because the tooltip needs two unrelated things: the
    // delegate *Item* to anchor under, and the *SystemTrayItem* to read a
    // label off. Reaching the latter through the former
    // (`hoveredIcon.modelData`) would mean reading a required property through
    // an Item-typed handle, which no type checker can verify.
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
    // Clock.qml's popupLoader. Simpler than Clock's and Weather's, since
    // Tooltip has no close grace period: `active` can mirror `show` directly
    // instead of needing an onVisibleChanged teardown hook.
    LazyLoader {
        active: root.hoveredIcon !== null

        Tooltip {
            anchorItem: root.hoveredIcon || root
            show: root.hoveredIcon !== null
            // `title` first: some apps report garbage in their SNI tooltip
            // text.
            text: root.hoveredItem ? (root.hoveredItem.title || root.hoveredItem.tooltipTitle || root.hoveredItem.id) : ""
        }
    }
}
