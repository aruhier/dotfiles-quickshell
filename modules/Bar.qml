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

    // Everything above the border stripe — the actual 22px-tall bar content,
    // matching waybar's "height": 22 (the border is genuine extra height
    // below it, not an overlay on top of it).
    Item {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: theme.barHeight

        // ---- left ----
        // Flush against the screen edge, rounded only on the inner (right)
        // side — mirrors .modules-left's one-sided pill in style.css (it
        // isn't a floating capsule with margins on both sides).
        Rectangle {
            id: leftGroup
            color: theme.groupBg
            topRightRadius: height / 2
            bottomRightRadius: height / 2
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // Only the inner (right) edge gets theme.groupEdgePadding, so
            // the outer/flush edge sits flush against the screen edge like
            // waybar (see leftRow's anchors below; a symmetric centerIn here
            // previously added a spurious pad on the flush side too). No
            // extra outer-edge margin here (unlike rightGroup below):
            // Mpd's icon glyph's own left-side bearing already lands its ink
            // ~10px from the edge, matching a real waybar screenshot
            // (measured pixel-for-pixel, see AGENT.md) — adding
            // theme.moduleOuterMargin here too would overshoot to ~14px.
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
            // Mirror of leftGroup: only the inner (left) edge gets
            // theme.groupEdgePadding. Unlike leftGroup, the outer/flush edge
            // here DOES need theme.moduleOuterMargin: Clock (the outermost
            // module here) ends in a plain digit, whose glyph has near-zero
            // right-side bearing, so without an explicit allowance for the
            // module's own CSS `margin: 0 4px` its ink lands only ~7px from
            // the screen edge instead of waybar's measured 10px (Mpd on the
            // left avoids needing this only because its icon glyph's own
            // left bearing happens to fill the gap — see leftGroup).
            implicitWidth: rightRow.implicitWidth + theme.groupEdgePadding + theme.moduleOuterMargin

            RowLayout {
                id: rightRow
                anchors.right: parent.right
                anchors.rightMargin: theme.moduleOuterMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                // Tray/Privacy/Weather are DP-1-only (see isDp1 above) and
                // each carry real per-instance cost beyond a bare Item — Tray
                // decodes/uploads a texture per systray icon, Privacy and
                // Weather each mount their own hover popup — so they're
                // wrapped in a Loader gated on isDp1 instead of just being
                // built and hidden via `visible`. A plain `visible: false`
                // instance still fully exists (still runs, still costs
                // memory/CPU) on the two non-DP1 bars; Loader with
                // `active: false` never instantiates the component at all.
                // isDp1 is fixed for a given bar's lifetime (derived from
                // modelData.name, which doesn't change), so `active` here
                // never toggles after creation — unlike Privacy's own
                // internal `visible: micActive`, which still needs to keep
                // animating the smooth width-collapse once loaded (see
                // Layout.preferredWidth below).
                Loader {
                    active: barWindow.isDp1
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
                    // Privacy's own `visible: micActive` (inside Privacy.qml)
                    // still needs to be tracked dynamically here, unlike
                    // Tray/Weather's static isDp1-only condition above.
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
