import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../shared"

// Mirrors waybar's "tray" module.
Item {
    id: root

    // Matches waybar's shared `padding: 0 6px` module rule.
    implicitWidth: row.implicitWidth + 12
    implicitHeight: Theme.barHeight
    clip: true

    // Currently-hovered delegate Item, or null. One Tooltip PopupWindow is
    // shared across every tray icon instead of each delegate owning its
    // own — a PopupWindow is a real compositor surface, and only one can
    // ever be shown at a time anyway (MouseAreas don't overlap), so N-1 of
    // them just sat there idle for the process lifetime.
    property Item hoveredIcon: null

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.resizeDuration
            easing.type: Theme.resizeEasing
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        // Matches waybar's config.d/common.json "tray": { "spacing": 20 }.
        spacing: 20

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayIcon
                required property var modelData

                // Matches waybar's "tray": { "icon-size": 14 }.
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
                        if (containsMouse)
                            root.hoveredIcon = trayIcon;
                        else if (root.hoveredIcon === trayIcon)
                            root.hoveredIcon = null;
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
                    if (root.hoveredIcon === trayIcon)
                        root.hoveredIcon = null;
                }
            }
        }
    }

    Tooltip {
        anchorItem: root.hoveredIcon || root
        show: root.hoveredIcon !== null
        // `title` first: some apps report garbage in their SNI tooltip
        // text; `title` is reliably clean.
        text: root.hoveredIcon ? (root.hoveredIcon.modelData.title || root.hoveredIcon.modelData.tooltipTitle || root.hoveredIcon.modelData.id) : ""
    }
}
