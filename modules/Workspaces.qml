pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.shared
import qs.shared.animations

// Workspace pill row: every workspace on every monitor, shown on every bar.
// Colors: has windows = workspaceBg, empty = workspaceEmptyBg, system-focused
// = accent (drawn by the sliding `selection` indicator), urgent =
// workspaceUrgent. A workspace active on its own monitor but not
// system-focused is bolded with a blended background instead.
Rectangle {
    id: root

    // This bar's own output name, to tell "active on this monitor" apart from
    // "active on some other monitor".
    required property string screenName

    readonly property int capWidth: Theme.centerCapWidth

    color: Theme.workspaceEmptyBg
    radius: height / 2
    readonly property real targetWidth: row.implicitWidth + capWidth * 2
    // Math.round(), not the raw float: this Rectangle (like wsDelegate and
    // selection below) has antialiasing off for crisp flush edges, and a
    // continuously-varying sub-pixel width rounds inconsistently frame to
    // frame as it eases — which reads as a faint shimmer rather than smooth
    // motion. The old ~60Hz-capped SpringAnimation had the same issue but
    // sampled 4x less often, muddying it into the motion.
    implicitWidth: Math.round(widthSpring.value)
    implicitHeight: row.implicitHeight
    clip: true

    WorkspaceFrameSpring {
        id: widthSpring
        group: sharedSprings
        to: root.targetWidth
    }

    // One clock for every spring in this file (this pill's width, each
    // delegate's width, and the selection indicator's three) instead of an
    // independent FrameAnimation each. They must advance by the identical dt
    // to stay locked together — the selection square is overlaid on its
    // focused delegate and has to track its edges pixel for pixel, and
    // independent drivers measure elapsed time separately (measured: two
    // standalone springs chasing one target differ in the 2nd decimal at the
    // "same" moment, which compounds into visible wobble at 240Hz).
    //
    // Springs register by declaring `group: sharedSprings`, and the driver
    // only runs while one of them has motion left, so nothing here has to
    // start or stop it. See SpringGroup.qml.
    SpringGroup {
        id: sharedSprings
    }

    // Shared metrics for pill sizing, instead of an invisible Text per
    // delegate — the font is constant, only the string differs.
    FontMetrics {
        id: wsMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // `selection` and the label Repeater are deliberately siblings of `row`,
    // not children: this Qt build's QtQuick.Layouts has no "ignoreLayout"
    // opt-out that would let them live inside a RowLayout unmanaged, and a
    // non-Layout wrapper around `row` wouldn't help either — its position
    // would still snap instantly, exactly as `row.x` does. See
    // `selection.rowTargetXOffset` for how that snap is handled.
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
                // lastIpcObject.windows is a point-in-time snapshot that isn't
                // kept in sync as windows open and close, so it can go stale
                // indefinitely. Count live windows via toplevels instead.
                readonly property int windows: wsDelegate.modelData.toplevels ? wsDelegate.modelData.toplevels.values.length : 0
                // True only for the pill on this bar's own monitor —
                // modelData.active is true once per monitor at a time.
                readonly property bool activeOnThisScreen: wsDelegate.modelData.active && wsDelegate.modelData.monitor !== null && wsDelegate.modelData.monitor.name === root.screenName
                // Active on this monitor, but this monitor isn't the focused
                // one.
                readonly property bool activeNotFocused: activeOnThisScreen && !wsDelegate.modelData.focused

                visible: !isSpecial
                Layout.preferredHeight: isSpecial ? 0 : Theme.barHeight
                // 34px minimum for a comfortable button size, measured by eye.
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

                // The focused fill is drawn by the shared `selection`
                // indicator below, not here.
                color: wsDelegate.modelData.urgent ? Theme.workspaceUrgent : activeNotFocused ? Theme.workspaceActiveBg : windows > 0 ? Theme.workspaceBg : Theme.workspaceEmptyBg

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wsDelegate.modelData.activate()
                }
            }
        }
    }

    // Shared square that slides and resizes to whichever delegate is focused,
    // rather than each delegate snapping its own fill. Painted above `row`,
    // below the labels.
    Rectangle {
        id: selection
        visible: root.focusedDelegate !== null
        color: Theme.accent
        antialiasing: false

        // The focused delegate's offset *within* row, sprung on its own. This
        // and rowTargetXOffset below are two separate springs whose animated
        // results are summed, rather than one spring over the sum: a single
        // gated spring freezes during the gap between a workspace being
        // destroyed and Hyprland reporting the new focus target, then catches
        // up in one jump; a single spring reading row.x live instead sums a
        // live row.x against a frozen local offset and lands on an arbitrary
        // point, usually a neighbouring pill.
        //
        // Sticky fallback (`: focusedTargetLocalX`, not `: 0`): Hyprland
        // delivers "workspace destroyed" and "new workspace focused" as
        // separate updates, so focusedDelegate can be null for a frame while
        // switching away from an empty workspace. Falling back to 0 would snap
        // the indicator to row's origin and back; holding the last value parks
        // it until the real target resolves.
        property real focusedTargetLocalX: root.focusedDelegate ? root.focusedDelegate.x : focusedTargetLocalX
        WorkspaceFrameSpring {
            id: focusedLocalXSpring
            group: sharedSprings
            to: selection.focusedTargetLocalX
        }

        // row.x mirrored through its own spring rather than read live. It's a
        // plain RowLayout-managed property, so it snaps the instant a delegate
        // is destroyed, while focusedLocalXSpring only reaches its new target
        // on the next tick. Reading it live added an already-new row.x to a
        // still-old local offset for one frame, which reproducibly overflowed
        // root's not-yet-shrunk edge by ~2px whenever a focused workspace was
        // destroyed.
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

    // Static top layer of labels, positioned over their matching delegate but
    // never moving themselves — only `selection` slides. Reads row.x/bgItem.x
    // live (unsprung) on purpose: labels aren't animated, so they always match
    // the pills' actual position with no spring lag of their own.
    Repeater {
        model: Hyprland.workspaces

        delegate: StyledText {
            id: wsLabel
            required property var modelData
            required property int index

            // repeater.itemAt() alone never re-evaluates once items exist;
            // reading repeater.count (a real NOTIFY property) keeps this live.
            readonly property var bgItem: repeater.count > wsLabel.index ? repeater.itemAt(wsLabel.index) : null

            visible: bgItem ? bgItem.visible : false
            x: bgItem ? row.x + bgItem.x + (bgItem.width - implicitWidth) / 2 : 0
            y: bgItem ? row.y + bgItem.y + (bgItem.height - implicitHeight) / 2 : 0
            text: wsLabel.modelData.name
            color: wsLabel.modelData.focused ? Theme.accentText : Theme.workspaceEmptyText
            font.bold: wsLabel.modelData.focused || (bgItem && bgItem.activeOnThisScreen)
        }
    }

    // Index of the focused workspace, -1 if none.
    readonly property int focusedIndex: {
        const wss = Hyprland.workspaces.values;
        for (let i = 0; i < wss.length; i++) {
            if (wss[i].focused)
                return i;
        }
        return -1;
    }
    // repeater.count again, for the same reason as bgItem above.
    readonly property var focusedDelegate: repeater.count > 0 && focusedIndex >= 0 ? repeater.itemAt(focusedIndex) : null
}
