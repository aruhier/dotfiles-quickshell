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

    // .modules-center's cream border-left/right (theme.centerCapWidth),
    // rounded into caps by the pill radius; buttons themselves have
    // border-radius: 0.
    readonly property int capWidth: theme.centerCapWidth

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
                // CSS gives buttons 18px padding (10 left + 8 right), but a
                // real waybar screenshot shows every single-character button
                // at a consistent ~34px regardless of glyph — GTK's default
                // button chrome (Adwaita's own min-width/border, baked into
                // libgtk3's compiled-in theme resources, not visible in
                // style.css) adds real width waybar's CSS alone doesn't
                // account for. Measured directly off a waybar screenshot
                // (three separate button blocks all landed within 1px of
                // 34px/button), not derived from any stylesheet value.
                Layout.preferredWidth: isSpecial ? 0 : Math.round(Math.max(label.implicitWidth + 18, 34))
                // Buttons are square (no radius) and sit flush edge-to-edge;
                // fractional per-item widths from RowLayout can leave a
                // stray 1px gap between two buttons where root's own fill
                // peeks through — rounding the width above avoids that, and
                // this avoids antialiasing softening the shared edge too.
                antialiasing: false

                color: modelData.urgent ? root.theme.workspaceUrgent
                    : modelData.focused ? root.theme.accent
                    : windows > 0 ? root.theme.workspaceBg
                    : root.theme.workspaceEmptyBg

                Text {
                    renderType: Text.NativeRendering
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
