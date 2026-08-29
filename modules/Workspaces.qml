import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

// Mirrors waybar's "hyprland/workspaces" module with all-outputs: true —
// every workspace on every monitor is shown on every bar.
Rectangle {
    id: root

    required property var theme
    required property var barScreen

    color: theme.workspaceBg
    radius: height / 2
    implicitWidth: row.implicitWidth + 4
    implicitHeight: row.implicitHeight + 4

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: wsDelegate
                required property var modelData

                // waybar's hyprland/workspaces hides special workspaces
                // unless "show-special" is set, which our config doesn't.
                readonly property bool isSpecial: modelData.name.startsWith("special")

                readonly property bool onThisMonitor: modelData.monitor !== null
                    && Hyprland.monitorFor(root.barScreen) !== null
                    && modelData.monitor.name === Hyprland.monitorFor(root.barScreen).name

                visible: !isSpecial
                Layout.preferredHeight: isSpecial ? 0 : root.theme.barHeight - 4
                Layout.preferredWidth: isSpecial ? 0 : label.implicitWidth + 18

                color: modelData.urgent ? root.theme.workspaceUrgent
                    : modelData.active ? root.theme.accent
                    : root.theme.workspaceEmptyBg

                border.width: (modelData.active && onThisMonitor) ? 1 : 0
                border.color: "#BF0905"

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData.name
                    color: modelData.active ? root.theme.accentText : root.theme.workspaceEmptyText
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSize
                    font.bold: modelData.active
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()
                }
            }
        }
    }
}
