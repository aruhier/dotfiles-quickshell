import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../shared"

// Mirrors waybar's "hyprland/workspaces" with all-outputs: true — every
// workspace on every monitor shown on every bar. Colors match style.css:
// default (has windows) = workspaceBg, .empty = workspaceEmptyBg,
// .active (waybar's isActive(), i.e. quickshell's "focused") = accent,
// .urgent = workspaceUrgent.
// Beyond waybar: a workspace active on its own monitor (but not the
// system-focused one) also gets bolded + a blended background instead of
// the sliding accent indicator — see wsDelegate.activeOnThisScreen/
// activeNotFocused.
Rectangle {
    id: root

    // This bar's own output name, to tell "active on this monitor" apart
    // from "active on some other monitor".
    required property string screenName

    readonly property int capWidth: Theme.centerCapWidth

    color: Theme.workspaceEmptyBg
    radius: height / 2
    implicitWidth: row.implicitWidth + capWidth * 2
    implicitHeight: row.implicitHeight
    clip: true

    Behavior on implicitWidth {
        SpringAnimation {
            spring: Theme.workspaceSpringSpring
            damping: Theme.workspaceSpringDamping
            epsilon: Theme.springEpsilon
        }
    }

    // Shared text metrics for pill sizing, instead of an invisible Text per
    // delegate — font is constant across delegates, only the string differs.
    FontMetrics {
        id: wsMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // `row` sizes/positions purely from its own children (RowLayout
    // recomputes synchronously — its width/x can snap the instant a
    // delegate is added or removed, same as it always has). `selection`
    // and the label Repeater are deliberately kept as its *siblings* here,
    // not reparented inside it — QtQuick.Layouts has no "ignoreLayout"
    // opt-out on this Qt build (confirmed against plugins.qmltypes) that
    // would let them live inside a RowLayout without being managed as
    // layout cells, and a non-Layout wrapper Item around `row` doesn't
    // actually help either: that wrapper's own position would *still* snap
    // instantly for the same reason `row.x` does, so nothing would be
    // gained over keeping `row` as-is. See `selection.targetX` below for
    // how the resulting instant-snap is actually handled.
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

                readonly property bool isSpecial: modelData.name.startsWith("special")
                // lastIpcObject.windows is a point-in-time snapshot that isn't
                // kept in sync as windows open/close — opening/closing a
                // window doesn't refresh it, so it can go stale indefinitely.
                // Count live windows via toplevels instead.
                readonly property int windows: modelData.toplevels ? modelData.toplevels.values.length : 0
                // True only for the pill on this bar's own monitor —
                // modelData.active is true once per monitor at a time.
                readonly property bool activeOnThisScreen: modelData.active
                    && modelData.monitor !== null && modelData.monitor.name === root.screenName
                // Active on this monitor but this monitor isn't the
                // system-focused one.
                readonly property bool activeNotFocused: activeOnThisScreen && !modelData.focused

                visible: !isSpecial
                Layout.preferredHeight: isSpecial ? 0 : Theme.barHeight
                // 34px empirical minimum from a waybar screenshot (GTK's own
                // button chrome isn't in style.css, only measurable).
                Layout.preferredWidth: isSpecial ? 0 : Math.round(Math.max(wsMetrics.advanceWidth(modelData.name) + 18, 34))
                Behavior on Layout.preferredWidth {
                    SpringAnimation {
                        spring: Theme.workspaceSpringSpring
                        damping: Theme.workspaceSpringDamping
                        epsilon: Theme.springEpsilon
                    }
                }
                // Square, flush buttons; rounding avoids stray 1px seams.
                antialiasing: false

                // Focused fill is drawn by the shared `selection` indicator
                // below, not here.
                color: modelData.urgent ? Theme.workspaceUrgent
                    : activeNotFocused ? Theme.workspaceActiveBg
                    : windows > 0 ? Theme.workspaceBg
                    : Theme.workspaceEmptyBg

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()
                }
            }
        }
    }

    // Shared square that slides/resizes to whichever delegate is focused,
    // instead of each delegate snapping its own fill. Painted above `row`
    // but below `labels`.
    Rectangle {
        id: selection
        visible: root.focusedDelegate !== null
        color: Theme.accent
        antialiasing: false

        // The focused delegate's offset *within* row, sprung on its own —
        // this is what should slide when focus moves between existing
        // workspaces.
        //
        // Three variants of this were tried and rejected before this one:
        // (1) a single spring over row.x + focusedDelegate.x summed and
        // gated together behind "focusedDelegate exists" — correct, but
        // freezes solid during the gap between a workspace being destroyed
        // and Hyprland reporting the new focus target, then has to catch up
        // in one motion, which reads as two disconnected steps; (2) the
        // same single spring but with row.x read live/ungated so it keeps
        // tracking row's reflow during that gap — smoother-looking in
        // principle, but sums a *live* row.x against a *frozen* local
        // offset from before the deletion, landing on a geometrically
        // arbitrary point that often coincides with a neighboring pill,
        // i.e. the indicator visibly jumps to the wrong workspace first and
        // then corrects. Springing each term separately (this version) and
        // summing the two *animated* results is what was actually shipped
        // and felt right — kept as-is; see rowXOffset below for why row.x
        // also needs its own mirrored spring rather than being read live.
        //
        // Sticky fallback (": focusedLocalX" not ": 0") — Hyprland's IPC
        // appears to deliver "workspace destroyed" and "new workspace
        // focused" as separate updates, not atomically, so focusedDelegate
        // can be transiently null for a frame while switching away from an
        // empty workspace. Falling back to 0 there would snap the target to
        // row's origin and back, flashing the indicator in the wrong place;
        // holding the last known value instead just leaves it parked until
        // the real focus target resolves.
        property real focusedLocalX: root.focusedDelegate ? root.focusedDelegate.x : focusedLocalX
        Behavior on focusedLocalX {
            SpringAnimation {
                spring: Theme.workspaceSpringSpring
                damping: Theme.workspaceSpringDamping
                epsilon: Theme.springEpsilon
            }
        }

        // row.x mirrored through its own spring rather than read live.
        // row.x is a plain RowLayout-managed geometry property — it snaps
        // *instantly* the moment a delegate is destroyed (RowLayout
        // recomputes synchronously), while focusedLocalX only reaches its
        // new target on the next animation tick (springs, doesn't jump).
        // Reading row.x live meant "already-new row.x" got added to
        // "still-old focusedLocalX" for one frame — confirmed via debug
        // logging: row.x jumping 15->32 instantly while focusedLocalX was
        // still at the previous focus's value (306) produced a real,
        // reproducible ~2px overflow past root's (not-yet-shrunk) edge
        // every time a focused workspace was destroyed. Springing this too
        // means both halves move smoothly together and can't mismatch by a
        // whole delegate-width in a single frame.
        property real rowXOffset: row.x
        Behavior on rowXOffset {
            SpringAnimation {
                spring: Theme.workspaceSpringSpring
                damping: Theme.workspaceSpringDamping
                epsilon: Theme.springEpsilon
            }
        }

        x: rowXOffset + focusedLocalX
        y: root.focusedDelegate ? row.y + root.focusedDelegate.y : y
        width: root.focusedDelegate ? root.focusedDelegate.width : width
        height: root.focusedDelegate ? root.focusedDelegate.height : height

        Behavior on width {
            SpringAnimation {
                spring: Theme.workspaceSpringSpring
                damping: Theme.workspaceSpringDamping
                epsilon: Theme.springEpsilon
            }
        }
    }

    // Static top layer of visible labels, positioned over their matching
    // delegate but never moving themselves — only `selection` slides. Reads
    // row.x/bgItem.x live (unsprung) on purpose: labels aren't animated at
    // all, so they always match the pills' actual current position exactly,
    // with no spring-lag of their own to desync against.
    Repeater {
        model: Hyprland.workspaces

        delegate: Text {
            id: wsLabel
            required property var modelData
            required property int index

            // repeater.itemAt() alone never re-evaluates once items exist;
            // reading repeater.count (a real NOTIFY property) keeps this live.
            readonly property var bgItem: repeater.count > index ? repeater.itemAt(index) : null

            renderType: Text.NativeRendering
            visible: bgItem ? bgItem.visible : false
            x: bgItem ? row.x + bgItem.x + (bgItem.width - implicitWidth) / 2 : 0
            y: bgItem ? row.y + bgItem.y + (bgItem.height - implicitHeight) / 2 : 0
            text: modelData.name
            color: modelData.focused ? Theme.accentText : Theme.workspaceEmptyText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: modelData.focused || (bgItem && bgItem.activeOnThisScreen)
        }
    }

    // Index of the focused workspace, -1 if none.
    readonly property int focusedIndex: {
        var wss = Hyprland.workspaces.values;
        for (var i = 0; i < wss.length; i++) {
            if (wss[i].focused)
                return i;
        }
        return -1;
    }
    // repeater.itemAt() alone never re-evaluates once items exist; reading
    // repeater.count (a real NOTIFY property) keeps this live.
    readonly property var focusedDelegate: repeater.count > 0 && focusedIndex >= 0 ? repeater.itemAt(focusedIndex) : null
}
