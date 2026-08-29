import QtQuick

// Color palette mirrored from ~/dotfiles/waybar/style.css so the quickshell
// bar looks like the waybar setup it replaces.
QtObject {
    readonly property color barBg: "#2d2d2d"
    readonly property color barBorder: "#6AA099"
    readonly property color text: "#A3A3AB"
    readonly property color textBright: "#E5D4CE"

    readonly property color groupBg: "#424242"
    readonly property color groupText: "#E5D4CE"

    readonly property color accent: "#6AA099"
    readonly property color accentText: "#2d2d2d"

    readonly property color workspaceBg: "#9BBFBA"
    readonly property color workspaceEmptyBg: "#E5D4CE"
    readonly property color workspaceEmptyText: "#252527"
    readonly property color workspaceUrgent: "#F98BA4"

    readonly property color critical: "#f53c3c"
    readonly property color privacyActive: "#D14005"

    readonly property string fontFamily: "Symbols Nerd Font Mono, Inter Variable, Material Design Icons Desktop"
    readonly property int fontSize: 12
    readonly property int barHeight: 22
}
