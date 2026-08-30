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
    implicitHeight: theme.barHeight + theme.barBorderHeight
    exclusionMode: ExclusionMode.Auto
    color: theme.barBg

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: theme.barBorderHeight
        color: theme.barBorder
    }

    // The 22px content area above the border stripe (border is extra
    // height below it, not an overlay).
    Item {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: theme.barHeight

        // ---- left ----
        // Flush against the screen edge, rounded only on the inner side —
        // mirrors .modules-left's one-sided pill.
        Rectangle {
            id: leftGroup
            color: theme.groupBg
            topRightRadius: height / 2
            bottomRightRadius: height / 2
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // Only the inner edge gets groupEdgePadding; no outer margin
            // here since Mpd's own glyph bearing already lands its ink at
            // the right spot (unlike rightGroup, see below).
            implicitWidth: leftRow.implicitWidth + theme.groupEdgePadding
            visible: leftRow.implicitWidth > 0

            RowLayout {
                id: leftRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
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
            screenName: barWindow.modelData.name
        }

        // ---- right ----
        Rectangle {
            id: rightGroup
            color: theme.groupBg
            topLeftRadius: height / 2
            bottomLeftRadius: height / 2
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // Mirror of leftGroup, but the outer edge here needs
            // moduleOuterMargin too: Clock ends in a digit with near-zero
            // right bearing, so it needs the explicit margin to match
            // waybar's spacing.
            implicitWidth: rightRow.implicitWidth + theme.groupEdgePadding + theme.moduleOuterMargin

            RowLayout {
                id: rightRow
                anchors.right: parent.right
                anchors.rightMargin: theme.moduleOuterMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                // Tray/Privacy/Weather are DP-1-only and each cost more than
                // a bare Item (icon textures, hover popups), so they're
                // Loader-gated instead of just hidden via `visible`.
                Loader {
                    active: barWindow.isDp1
                    // `active: false` alone leaves a visible zero-width item,
                    // which still reserves RowLayout spacing on both sides;
                    // `visible: active` excludes it properly.
                    visible: active
                    Layout.preferredWidth: item ? item.implicitWidth : 0
                    sourceComponent: Tray {
                        theme: barWindow.theme
                    }
                }
                Backlight {
                    theme: barWindow.theme
                }
                Volume {
                    theme: barWindow.theme
                }
                Loader {
                    active: barWindow.isDp1
                    // Also tracks Privacy's own visible: micActive once
                    // loaded, not just isDp1.
                    visible: item ? item.visible : false
                    Layout.preferredWidth: item && item.visible ? item.implicitWidth : 0
                    sourceComponent: Privacy {
                        theme: barWindow.theme
                    }
                }
                SwayNC {
                    theme: barWindow.theme
                }
                Loader {
                    active: barWindow.isDp1
                    visible: active
                    Layout.preferredWidth: item ? item.implicitWidth : 0
                    sourceComponent: Weather {
                        theme: barWindow.theme
                    }
                }
                Clock {
                    theme: barWindow.theme
                }
            }
        }
    }
}
