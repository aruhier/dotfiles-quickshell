pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.shared
import qs.shared.popup

// Hover popup below a workspace pill: a scaled-down live mock-up of that
// workspace, one ScreencopyView per window placed at the window's real
// position on its monitor. Hyprland can capture outputs and individual
// windows but has no notion of capturing a workspace, so this composes the
// windows itself — which is also what makes it work for workspaces that
// aren't on screen right now: the compositor re-renders each window offscreen
// for its capture (verified on Hyprland 0.56.2, see AGENTS.md).
HoverPopup {
    id: popup

    required property HyprlandWorkspace workspace

    padding: 6

    // Window geometry comes from lastIpcObject, which is a snapshot that goes
    // stale as windows get tiled and resized — so re-fetch it once per open.
    // Creation is the open: the popup is built by a LazyLoader on hover.
    Component.onCompleted: Hyprland.refreshToplevels()

    readonly property HyprlandMonitor monitor: workspace.monitor

    // hyprctl's window `at`/`size` and the monitor's `x`/`y` are logical
    // (scale-divided) global coordinates, but the monitor's `width`/`height`
    // are the physical mode size, so divide the scale back out. Odd
    // transforms are 90°/270° rotations, which swap the axes.
    readonly property bool rotated: monitor ? (monitor.lastIpcObject.transform ?? 0) % 2 === 1 : false
    readonly property real monitorWidth: monitor ? (rotated ? monitor.height : monitor.width) / monitor.scale : 0
    readonly property real monitorHeight: monitor ? (rotated ? monitor.width : monitor.height) / monitor.scale : 0
    readonly property real monitorX: monitor ? monitor.x : 0
    readonly property real monitorY: monitor ? monitor.y : 0
    readonly property real scaleFactor: monitorWidth > 0 ? Theme.workspacePreviewWidth / monitorWidth : 0

    // Bottom-to-top paint order: tiled, then floating, then fullscreen, each
    // group least-recently-focused first (focusHistoryID 0 = most recent).
    // hyprctl's own order is creation order, which says nothing about
    // stacking. A window without geometry yet (lastIpcObject still empty)
    // is left out until the refresh above lands.
    readonly property var windows: workspace.toplevels.values.filter(t => t.lastIpcObject.mapped && !t.lastIpcObject.hidden).sort((a, b) => {
        const layer = ipc => ipc.fullscreen ? 2 : ipc.floating ? 1 : 0;
        return layer(a.lastIpcObject) - layer(b.lastIpcObject) || b.lastIpcObject.focusHistoryID - a.lastIpcObject.focusHistoryID;
    })

    visible: _open && monitor !== null && windows.length > 0

    implicitWidth: Theme.workspacePreviewWidth + 2 * padding
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

                    x: Math.round((ipc.at[0] - popup.monitorX) * popup.scaleFactor)
                    y: Math.round((ipc.at[1] - popup.monitorY) * popup.scaleFactor)
                    width: Math.round(ipc.size[0] * popup.scaleFactor)
                    height: Math.round(ipc.size[1] * popup.scaleFactor)

                    captureSource: view.modelData.wayland
                    // Keep capturing while shown; the view is destroyed with the
                    // popup, so nothing runs once it's closed.
                    live: true
                }
            }
        }

        // Footer: the workspace name on an accent strip, echoing the
        // focused pill in the bar.
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
