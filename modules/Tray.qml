pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.shared
import qs.shared.popup
import qs.themes

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

                // Full bar height, so the whole height is clickable and the
                // tooltip anchors below the bar like every other module's.
                Layout.preferredWidth: 14
                Layout.preferredHeight: Theme.barHeight

                IconImage {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    source: trayIcon.modelData.icon
                    implicitSize: 14
                }

                MouseArea {
                    anchors.fill: parent
                    // Half the spacing either side: no dead gap between icons,
                    // so the cursor crossing one doesn't drop the tooltip.
                    anchors.leftMargin: -row.spacing / 2
                    anchors.rightMargin: -row.spacing / 2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
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
                    // Raw deltas: the StatusNotifierItem protocol wants them.
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y !== 0)
                            trayIcon.modelData.scroll(wheel.angleDelta.y, false);
                        if (wheel.angleDelta.x !== 0)
                            trayIcon.modelData.scroll(wheel.angleDelta.x, true);
                    }
                }

                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayIcon.modelData.menu
                    anchor.item: trayIcon
                    // Stretched past the border stripe, so the menu opens
                    // below the bar rather than over its bottom edge.
                    anchor.rect.width: trayIcon.width
                    anchor.rect.height: trayIcon.height + Theme.barBorderHeight + 1
                    anchor.edges: Edges.Bottom | Edges.Left
                    anchor.gravity: Edges.Bottom | Edges.Right
                    onOpened: PopupCoordinator.trayMenuOwner = trayIcon
                    onClosed: if (PopupCoordinator.trayMenuOwner === trayIcon)
                        PopupCoordinator.trayMenuOwner = null
                }

                // An app quitting while its tooltip shows would otherwise
                // leave hoveredIcon pointing at a destroyed delegate.
                // Same for a menu left open: its `closed` may never come.
                Component.onDestruction: {
                    if (root.hoveredIcon === trayIcon) {
                        root.hoveredIcon = null;
                        root.hoveredItem = null;
                    }
                    if (PopupCoordinator.trayMenuOwner === trayIcon)
                        PopupCoordinator.trayMenuOwner = null;
                }
            }
        }
    }

    // Not while a tray menu is open: it would sit on top of, or under, it.
    readonly property bool tooltipWanted: hoveredIcon !== null && PopupCoordinator.trayMenuOwner === null

    // LazyLoader, not Loader: Tooltip is a PopupWindow, not an Item — see
    // HoverPopupArea.qml. No close grace period here, so `active` can
    // mirror `show` instead of needing a teardown hook.
    LazyLoader {
        active: root.tooltipWanted

        Tooltip {
            anchorItem: root.hoveredIcon || root
            show: root.tooltipWanted
            // `title` first — some apps report garbage in tooltipTitle.
            text: root.hoveredItem ? (root.hoveredItem.title || root.hoveredItem.tooltipTitle || root.hoveredItem.id) : ""
        }
    }
}
