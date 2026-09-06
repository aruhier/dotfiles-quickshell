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

    // One Tooltip PopupWindow is shared across every tray icon instead of
    // each delegate owning its own — a PopupWindow is a real compositor
    // surface, and only one can ever be shown at a time anyway (MouseAreas
    // don't overlap), so N-1 of them just sat there idle for the process
    // lifetime.
    //
    // Two properties, not one, because the tooltip needs two unrelated
    // things: the delegate *Item* to anchor the popup under, and the
    // *SystemTrayItem* to read a label off. Reaching the latter through the
    // former (`hoveredIcon.modelData`) meant reading a delegate's required
    // property through an `Item`-typed handle — which no type checker can
    // verify, and which silently returns undefined the moment a delegate
    // stops declaring it.
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
                    id: hover
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

                // Guard against a tray icon disappearing mid-hover (app
                // quits while its tooltip is showing) leaving root.hoveredIcon
                // pointing at a destroyed delegate.
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
    // Clock.qml's popupLoader for the rationale (a real GPU-backed window
    // otherwise kept alive for the process lifetime after first use).
    // Simpler than Clock's/Weather's: Tooltip has no close grace period
    // (HoverPopup.qml's comment explains why), so 'active' can just mirror
    // 'show' directly instead of needing an onVisibleChanged teardown hook.
    LazyLoader {
        active: root.hoveredIcon !== null

        Tooltip {
            anchorItem: root.hoveredIcon || root
            show: root.hoveredIcon !== null
            // `title` first: some apps report garbage in their SNI tooltip
            // text; `title` is reliably clean.
            text: root.hoveredItem ? (root.hoveredItem.title || root.hoveredItem.tooltipTitle || root.hoveredItem.id) : ""
        }
    }
}
