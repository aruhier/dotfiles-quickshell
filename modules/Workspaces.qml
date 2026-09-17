pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.shared
import qs.shared.animations
import qs.shared.popup
import qs.themes

// Workspace pill row: every workspace on every monitor, shown on every bar.
// Colors: has windows = workspaceBg, empty = workspaceEmptyBg, system-focused
// = accent (drawn by the sliding `selection` indicator), urgent =
// workspaceUrgent, active-but-not-focused = bolded workspaceActiveBg.
Rectangle {
    id: root

    // This bar's output, to tell "active here" from "active elsewhere".
    required property string screenName

    readonly property int capWidth: Theme.centerCapWidth

    color: Theme.workspaceEmptyBg
    radius: height / 2
    readonly property real targetWidth: row.implicitWidth + capWidth * 2
    // Math.round(): antialiasing is off here (and on wsDelegate/selection)
    // for crisp flush edges, so a sub-pixel width shimmers as it eases.
    implicitWidth: Math.round(widthSpring.value)
    implicitHeight: row.implicitHeight
    clip: true

    WorkspaceFrameSpring {
        id: widthSpring
        group: sharedSprings
        to: root.targetWidth
    }

    // One clock for every spring in this file: the selection square overlays
    // its focused delegate and must track its edges pixel for pixel, which
    // independent drivers can't do — they measure dt separately and drift into
    // visible wobble at 240Hz. Springs join by `group: sharedSprings`; see
    // SpringGroup.qml.
    SpringGroup {
        id: sharedSprings
    }

    // Pill sizing, instead of an invisible Text per delegate.
    FontMetrics {
        id: wsMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        // Both mirror StyledText: weight and hinting change advance widths,
        // so measuring without them sizes the pills off the wrong string.
        font.variableAxes: ({ "wght": Theme.fontWeight })
        font.hintingPreference: Font.PreferVerticalHinting
    }

    // `selection` and the label Repeater are siblings of `row`, not children:
    // this Qt build's Layouts has no "ignoreLayout" opt-out. See
    // `selection.rowTargetXOffset` for the resulting snap handling.
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            id: repeater
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: wsDelegate
                required property var modelData

                readonly property bool isSpecial: wsDelegate.modelData.name.startsWith("special")
                // Not lastIpcObject.windows — a snapshot that goes stale.
                readonly property int windows: wsDelegate.modelData.toplevels ? wsDelegate.modelData.toplevels.values.length : 0
                // modelData.active is true once per monitor, so qualify it.
                readonly property bool activeOnThisScreen: wsDelegate.modelData.active && wsDelegate.modelData.monitor !== null && wsDelegate.modelData.monitor.name === root.screenName
                readonly property bool activeNotFocused: activeOnThisScreen && !wsDelegate.modelData.focused

                visible: !isSpecial
                Layout.preferredHeight: isSpecial ? 0 : Theme.barHeight
                // 34px minimum for a comfortable button, measured by eye.
                readonly property real targetPreferredWidth: isSpecial ? 0 : Math.round(Math.max(wsMetrics.advanceWidth(wsDelegate.modelData.name) + 18, 34))
                // Math.round() — see root's implicitWidth above.
                Layout.preferredWidth: Math.round(preferredWidthSpring.value)

                WorkspaceFrameSpring {
                    id: preferredWidthSpring
                    group: sharedSprings
                    to: wsDelegate.targetPreferredWidth
                }
                // Square, flush buttons; rounding avoids stray 1px seams.
                antialiasing: false

                // The focused fill comes from `selection` below, not here.
                readonly property color stateColor: wsDelegate.modelData.urgent ? Theme.workspaceUrgent : activeNotFocused ? Theme.workspaceActiveBg : windows > 0 ? Theme.workspaceBg : Theme.workspaceEmptyBg
                readonly property bool hovered: mouseArea.hovered
                color: hovered ? Qt.darker(stateColor, Theme.workspaceHoverDarken) : stateColor

                // Hover previews the workspace; a click switches to it and
                // drops the preview along with any pending open.
                HoverPopupArea {
                    id: mouseArea
                    loader: previewLoader
                    popupEnabled: wsDelegate.windows > 0
                    onClicked: {
                        cancel();
                        wsDelegate.modelData.activate();
                    }
                }

                // LazyLoader, not Loader — see Clock.qml's popupLoader. Torn
                // down on close, since each ScreencopyView inside keeps a
                // capture running while alive.
                LazyLoader {
                    id: previewLoader
                    active: false

                    WorkspacePreviewPopup {
                        anchorItem: wsDelegate
                        workspace: wsDelegate.modelData
                        onVisibleChanged: {
                            if (!visible)
                                previewLoader.active = false;
                        }
                    }
                }
            }
        }
    }

    // Shared square that slides to the focused delegate, instead of each
    // delegate snapping its own fill. Above `row`, below the labels.
    Rectangle {
        id: selection
        visible: root.focusedDelegate !== null
        // Covers the focused delegate, so it mirrors its hover itself.
        color: root.focusedDelegate && root.focusedDelegate.hovered ? Qt.darker(Theme.accent, Theme.workspaceHoverDarken) : Theme.accent
        antialiasing: false

        // The offset *within* row, sprung separately from rowTargetXOffset
        // and summed: one spring over the sum either freezes and jumps, or
        // sums a live row.x against a frozen offset and lands on a neighbour.
        //
        // Sticky fallback (not `: 0`): Hyprland reports "destroyed" and "newly
        // focused" separately, so focusedDelegate is null for a frame — 0
        // would snap the indicator to row's origin and back.
        property real focusedTargetLocalX: root.focusedDelegate ? root.focusedDelegate.x : focusedTargetLocalX
        WorkspaceFrameSpring {
            id: focusedLocalXSpring
            group: sharedSprings
            to: selection.focusedTargetLocalX
        }

        // row.x sprung, not read live: RowLayout snaps it the instant a
        // delegate dies, which for one frame adds a new row.x to a still-old
        // local offset and overflowed root's edge by ~2px.
        property real rowTargetXOffset: row.x
        WorkspaceFrameSpring {
            id: rowXOffsetSpring
            group: sharedSprings
            to: selection.rowTargetXOffset
        }

        // Math.round() on x and width — see root's implicitWidth above.
        x: Math.round(rowXOffsetSpring.value + focusedLocalXSpring.value)
        y: root.focusedDelegate ? row.y + root.focusedDelegate.y : y
        property real targetSelectionWidth: root.focusedDelegate ? root.focusedDelegate.width : targetSelectionWidth
        height: root.focusedDelegate ? root.focusedDelegate.height : height

        WorkspaceFrameSpring {
            id: selectionWidthSpring
            group: sharedSprings
            to: selection.targetSelectionWidth
        }
        width: Math.round(selectionWidthSpring.value)
    }

    // Labels sit over their delegate and never animate, so they read
    // row.x/bgItem.x live — no spring lag of their own.
    Repeater {
        model: Hyprland.workspaces

        delegate: StyledText {
            id: wsLabel
            required property var modelData
            required property int index

            // itemAt() never re-evaluates on its own; reading repeater.count
            // (a real NOTIFY property) keeps this binding live.
            readonly property var bgItem: repeater.count > wsLabel.index ? repeater.itemAt(wsLabel.index) : null

            visible: bgItem ? bgItem.visible : false
            x: bgItem ? row.x + bgItem.x + (bgItem.width - implicitWidth) / 2 : 0
            y: bgItem ? row.y + bgItem.y + (bgItem.height - implicitHeight) / 2 : 0
            text: wsLabel.modelData.name
            color: wsLabel.modelData.focused ? Theme.accentText : Theme.workspaceEmptyText
            bold: wsLabel.modelData.focused || (bgItem && bgItem.activeOnThisScreen)
        }
    }

    // Index of the focused workspace, -1 if none — findIndex's own miss value.
    readonly property int focusedIndex: Hyprland.workspaces.values.findIndex(ws => ws.focused)
    // repeater.count again, for the same reason as bgItem above.
    readonly property var focusedDelegate: repeater.count > 0 && focusedIndex >= 0 ? repeater.itemAt(focusedIndex) : null
}
