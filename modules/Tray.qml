import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../shared"

// Mirrors waybar's "tray" module.
Item {
    id: root

    required property var theme

    // Matches waybar's shared module rule `padding: 0 6px` (same rule #mpd
    // uses), so the gap here lines up with the one on the right of #mpd.
    implicitWidth: row.implicitWidth + 12
    implicitHeight: theme.barHeight
    // Smooth resize as tray icons come and go — see Theme.qml's
    // resizeDuration. (Individual icons still pop in/out instantly; only
    // the module's overall width eases.)
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
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

                Tooltip {
                    anchorItem: trayIcon
                    theme: root.theme
                    show: hover.containsMouse
                    // `title` first, not `tooltipTitle`: some apps (e.g.
                    // CopyQ) report garbage in their SNI ToolTip text (seen
                    // in practice: a leaked FreeType/Qt debug string, not
                    // anything app-related) while `title` is reliably the
                    // clean app name for every app tested. Waybar's own
                    // src/modules/sni/item.cpp prefers tooltip.text first
                    // and would show the same garbage for a broken app like
                    // this; deviating here on purpose since showing a
                    // command-looking string instead of an app name is a
                    // real, visible bug worth avoiding.
                    text: trayIcon.modelData.title || trayIcon.modelData.tooltipTitle || trayIcon.modelData.id
                }
            }
        }
    }
}
