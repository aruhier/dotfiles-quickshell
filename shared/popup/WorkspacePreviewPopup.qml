pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.shared
import qs.shared.popup
import qs.themes

// Hover popup below a workspace pill: a scaled-down live mock-up, one
// ScreencopyView per window at the window's real position on its monitor.
// Composed window by window because Hyprland can capture outputs and windows
// but not workspaces — which is also why an off-screen workspace works, since
// each window is re-rendered offscreen for its capture. See notes/workspaces.md.
HoverPopup {
    id: popup

    required property HyprlandWorkspace workspace

    padding: 6

    // lastIpcObject's geometry goes stale as windows are tiled and resized,
    // so re-fetch on creation — which is the open, via LazyLoader.
    Component.onCompleted: Hyprland.refreshToplevels()

    readonly property HyprlandMonitor monitor: workspace.monitor

    // Window `at`/`size` and monitor `x`/`y` are logical coordinates, but
    // monitor `width`/`height` is the physical mode size — hence the scale
    // divide. Odd transforms are 90°/270° rotations, which swap the axes.
    readonly property bool rotated: monitor ? (monitor.lastIpcObject.transform ?? 0) % 2 === 1 : false
    readonly property real monitorWidth: monitor ? (rotated ? monitor.height : monitor.width) / monitor.scale : 0
    readonly property real monitorHeight: monitor ? (rotated ? monitor.width : monitor.height) / monitor.scale : 0
    readonly property real monitorX: monitor ? monitor.x : 0
    readonly property real monitorY: monitor ? monitor.y : 0
    // Width only; height follows the monitor's aspect ratio.
    readonly property int previewWidth: 560
    readonly property real scaleFactor: monitorWidth > 0 ? popup.previewWidth / monitorWidth : 0

    // The workspace's windows, whatever their state: this is the Repeater's
    // model, and it must only change when a window comes or goes. Which are
    // shown and how they stack is decided per delegate off `lastIpcObject`,
    // which the refresh above rewrites for every window — as the model, that
    // rebuilt every ScreencopyView on open, two capture set-ups per hover.
    readonly property var windows: workspace.toplevels.values
    readonly property int shownCount: windows.filter(t => popup.shows(t.lastIpcObject)).length

    function shows(ipc) {
        return ipc.mapped && !ipc.hidden;
    }

    // Bottom-to-top: tiled, floating, fullscreen, each group least-recently-
    // focused first (focusHistoryID 0 = most recent). The IPC order is
    // creation order, which says nothing about stacking. Kept positive: a
    // child with z < 0 paints behind its parent, under the backdrop.
    function stackOrder(ipc) {
        const layer = ipc.fullscreen ? 2 : ipc.floating ? 1 : 0;
        return layer * 1000 + Math.max(0, 999 - ipc.focusHistoryID);
    }

    visible: _open && monitor !== null && shownCount > 0

    implicitWidth: popup.previewWidth + 2 * padding
    implicitHeight: body.implicitHeight + 2 * padding

    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(popup.monitorHeight * popup.scaleFactor)
            color: Theme.workspacePreviewBg
            clip: true

            Repeater {
                model: popup.windows

                delegate: ScreencopyView {
                    id: view
                    required property HyprlandToplevel modelData

                    readonly property var ipc: view.modelData.lastIpcObject

                    visible: popup.shows(ipc)
                    z: popup.stackOrder(ipc)
                    x: Math.round((ipc.at[0] - popup.monitorX) * popup.scaleFactor)
                    y: Math.round((ipc.at[1] - popup.monitorY) * popup.scaleFactor)
                    width: Math.round(ipc.size[0] * popup.scaleFactor)
                    height: Math.round(ipc.size[1] * popup.scaleFactor)

                    captureSource: view.modelData.wayland
                    // The view dies with the popup, so nothing captures once
                    // it's closed; a hidden window's doesn't capture at all.
                    live: view.visible
                }
            }
        }

        // The workspace name on an accent strip, echoing the focused pill.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: footerLabel.implicitHeight + 8
            color: Theme.accent
            radius: 4

            StyledText {
                id: footerLabel
                anchors.centerIn: parent
                text: popup.workspace.name
                font.pixelSize: 14
                bold: true
                color: Theme.accentText
            }
        }
    }
}
