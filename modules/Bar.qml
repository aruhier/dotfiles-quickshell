import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../shared"

// One bar instance per output. Layout mirrors ~/.config/waybar/config:
// DP-1 gets tray/privacy/weather in addition to the shared modules.
PanelWindow {
    id: barWindow

    required property var modelData
    screen: modelData

    readonly property var theme: Theme {}
    readonly property bool isDp1: modelData.name === "DP-1"

    anchors {
        top: true
        left: true
        right: true
    }
    margins.bottom: 1
    implicitHeight: theme.barHeight
    exclusionMode: ExclusionMode.Auto
    color: theme.barBg

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 3
        color: theme.barBorder
    }

    // ---- left ----
    Rectangle {
        id: leftGroup
        color: theme.groupBg
        radius: height / 2
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: theme.barHeight - 2
        implicitWidth: leftRow.implicitWidth + 16
        visible: leftRow.implicitWidth > 0

        RowLayout {
            id: leftRow
            anchors.centerIn: parent
            spacing: 10

            Mpd {
                theme: barWindow.theme
            }
            Submap {
                theme: barWindow.theme
            }
        }
    }

    // ---- center ----
    Workspaces {
        anchors.centerIn: parent
        theme: barWindow.theme
        barScreen: barWindow.screen
    }

    // ---- right ----
    Rectangle {
        id: rightGroup
        color: theme.groupBg
        radius: height / 2
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: theme.barHeight - 2
        implicitWidth: rightRow.implicitWidth + 16

        RowLayout {
            id: rightRow
            anchors.centerIn: parent
            spacing: 10

            Tray {
                theme: barWindow.theme
                visible: barWindow.isDp1
                Layout.preferredWidth: visible ? implicitWidth : 0
            }
            Backlight {
                theme: barWindow.theme
            }
            Volume {
                theme: barWindow.theme
            }
            Privacy {
                theme: barWindow.theme
                visible: barWindow.isDp1
                Layout.preferredWidth: visible ? implicitWidth : 0
            }
            SwayNC {
                theme: barWindow.theme
            }
            Weather {
                theme: barWindow.theme
                visible: barWindow.isDp1
                Layout.preferredWidth: visible ? implicitWidth : 0
            }
            Clock {
                theme: barWindow.theme
            }
        }
    }
}
