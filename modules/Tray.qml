import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../shared"
import "../shared/animations"
import "../shared/popup"

// System tray.
Item {
    id: root

    // 6px padding on each side, matching every other module's horizontal
    // padding.
    readonly property real targetWidth: row.implicitWidth + 12
    implicitWidth: widthSpring.value
    implicitHeight: Theme.barHeight
    clip: true

    // Currently-hovered delegate Item, or null. One Tooltip PopupWindow is
    // shared across every tray icon instead of each delegate owning its
    // own — a PopupWindow is a real compositor surface, and only one can
    // ever be shown at a time anyway (MouseAreas don't overlap), so N-1 of
    // them just sat there idle for the process lifetime.
    property Item hoveredIcon: null

    // FrameSpring, not Behavior/WidthSpring — see Submap.qml's FrameSpring
    // for why (Behavior-based SpringAnimation is throttled to Qt Quick's
    // shared ~60Hz GUI-thread clock regardless of the output's real refresh
    // rate).
    FrameSpring {
        id: widthSpring
        Component.onCompleted: snapTo(root.targetWidth)
    }

    onTargetWidthChanged: widthSpring.retarget(targetWidth)

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
            text: root.hoveredIcon ? (root.hoveredIcon.modelData.title || root.hoveredIcon.modelData.tooltipTitle || root.hoveredIcon.modelData.id) : ""
        }
    }
}
