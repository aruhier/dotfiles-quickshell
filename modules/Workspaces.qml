import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

// Mirrors waybar's "hyprland/workspaces" module with all-outputs: true —
// every workspace on every monitor is shown on every bar. Matches
// ~/.config/waybar/style.css's #workspaces button rules:
//   - default (has windows): theme.workspaceBg
//   - .empty (0 windows):    theme.workspaceEmptyBg
//   - .active (waybar's isActive() = focused workspace of the focused
//     monitor, i.e. quickshell's "focused" — NOT quickshell's "active",
//     which is true once per monitor and would highlight several
//     workspaces at once): theme.accent, bold
//   - .urgent: theme.workspaceUrgent
// The button.visible.current_output box-shadow rule in style.css is dead
// CSS for hyprland/workspaces (that module never sets a "current_output"
// class, only sway/workspaces does), so it's intentionally not replicated.
Rectangle {
    id: root

    required property var theme

    // .modules-center's 15px cream border-left/right, rounded into caps by
    // the pill radius; buttons themselves have border-radius: 0.
    readonly property int capWidth: 15

    color: theme.workspaceEmptyBg
    radius: height / 2
    implicitWidth: row.implicitWidth + capWidth * 2
    implicitHeight: row.implicitHeight

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
                readonly property int windows: modelData.lastIpcObject && modelData.lastIpcObject.windows !== undefined
                    ? modelData.lastIpcObject.windows : 0

                visible: !isSpecial
                Layout.preferredHeight: isSpecial ? 0 : root.theme.barHeight
                Layout.preferredWidth: isSpecial ? 0 : label.implicitWidth + 18

                color: modelData.urgent ? root.theme.workspaceUrgent
                    : modelData.focused ? root.theme.accent
                    : windows > 0 ? root.theme.workspaceBg
                    : root.theme.workspaceEmptyBg

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData.name
                    color: modelData.focused ? root.theme.accentText : root.theme.workspaceEmptyText
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSize
                    font.bold: modelData.focused
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
