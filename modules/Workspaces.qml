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
//     workspaces at once): theme.accent
//   - .urgent: theme.workspaceUrgent
// Beyond waybar parity: each bar also bolds the workspace that's active on
// *its own* monitor, focused or not (see wsDelegate.activeOnThisScreen).
// When that monitor isn't the system-focused one, the pill also gets a
// blended background (Theme.qml's workspaceActiveBg) instead of the
// sliding accent `selection` indicator, which only ever follows the one
// true focused workspace — see wsDelegate.activeNotFocused.
// The button.visible.current_output box-shadow rule in style.css is dead
// CSS for hyprland/workspaces (that module never sets a "current_output"
// class, only sway/workspaces does), so it's intentionally not replicated.
Rectangle {
    id: root

    required property var theme
    // This bar's own output (e.g. "DP-1"), from Bar.qml's `screen`. Needed
    // to tell "active on this monitor" apart from "active on some other
    // monitor" — see wsDelegate.activeOnThisScreen.
    required property string screenName

    // .modules-center's cream border-left/right (theme.centerCapWidth),
    // rounded into caps by the pill radius; buttons themselves have
    // border-radius: 0.
    readonly property int capWidth: theme.centerCapWidth

    color: theme.workspaceEmptyBg
    radius: height / 2
    implicitWidth: row.implicitWidth + capWidth * 2
    implicitHeight: row.implicitHeight
    // Smooth resize as workspaces are created/destroyed — see Theme.qml's
    // resizeDuration.
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
        }
    }

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

                // waybar's hyprland/workspaces hides special workspaces
                // unless "show-special" is set, which our config doesn't.
                readonly property bool isSpecial: modelData.name.startsWith("special")
                readonly property int windows: modelData.lastIpcObject && modelData.lastIpcObject.windows !== undefined
                    ? modelData.lastIpcObject.windows : 0
                // Active on this bar's own monitor. modelData.active alone
                // is true once per monitor at a time, so without matching
                // against screenName every bar would mark one pill per
                // monitor instead of just its own.
                readonly property bool activeOnThisScreen: modelData.active
                    && modelData.monitor !== null && modelData.monitor.name === root.screenName
                // Active here, but this monitor isn't the system-focused
                // one (a workspace active on the focused monitor is always
                // also modelData.focused) — the "other monitor" case that
                // gets the blended background below instead of `selection`.
                readonly property bool activeNotFocused: activeOnThisScreen && !modelData.focused

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
                // Bold (focused) vs regular metrics shift a button's own
                // width slightly — smooth that too, same tuning as the
                // group's own resize (Theme.qml's resizeDuration).
                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: root.theme.resizeDuration
                        easing.type: root.theme.resizeEasing
                    }
                }
                // Buttons are square (no radius) and sit flush edge-to-edge;
                // fractional per-item widths from RowLayout can leave a
                // stray 1px gap between two buttons where root's own fill
                // peeks through — rounding the width above avoids that, and
                // this avoids antialiasing softening the shared edge too.
                antialiasing: false

                // Focused look (accent fill) is drawn once by the shared
                // `selection` indicator below, not here — it slides between
                // delegates instead of each one snapping its own color.
                // activeNotFocused gets its own static background instead,
                // since `selection` only ever tracks the one focused index.
                color: modelData.urgent ? root.theme.workspaceUrgent
                    : activeNotFocused ? root.theme.workspaceActiveBg
                    : windows > 0 ? root.theme.workspaceBg
                    : root.theme.workspaceEmptyBg

                // Invisible — exists only so Layout.preferredWidth above has
                // something to measure. The actual, visible label for every
                // workspace lives in the separate `labels` Repeater below,
                // stacked on top of `selection`: labels need to stay fixed
                // in place while only the colored square slides underneath
                // them (see `labels`' comment), which isn't possible if the
                // label is a child of this delegate — a sibling can only be
                // painted fully above or fully below another sibling's whole
                // subtree, never "above this delegate's fill but below that
                // delegate's text" for many delegates at once.
                Text {
                    id: label
                    visible: false
                    text: modelData.name
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSize
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()
                }
            }
        }
    }

    // Index of the focused delegate within Hyprland.workspaces (not the
    // Repeater's own items — reading `.values` off the model directly is
    // the same pattern Privacy.qml uses to scan Pipewire.nodes.values, and
    // keeps this independent of whether/when the Repeater has instantiated
    // each item). -1 when nothing is focused (e.g. briefly during startup).
    readonly property int focusedIndex: {
        var wss = Hyprland.workspaces.values;
        for (var i = 0; i < wss.length; i++) {
            if (wss[i].focused)
                return i;
        }
        return -1;
    }
    // The actual delegate Rectangle currently focused, if any — read via
    // Repeater.itemAt() so `selection` below can mirror its live geometry
    // (x/width already ease via that delegate's own Layout.preferredWidth
    // Behavior above; sharing the same index keeps both in sync).
    // `repeater.itemAt()` is a plain method call, not a property read, so a
    // binding that calls it without also reading a real NOTIFY-backed
    // property (here, `count`) never re-evaluates once the Repeater
    // actually finishes creating that item — it silently stays null forever
    // if this binding's first evaluation happened to race ahead of the
    // Repeater populating (which it did: this made the indicator invisible
    // from launch, with no warning anywhere, until a focus change flipped
    // focusedIndex and forced a re-evaluation).
    readonly property var focusedDelegate: repeater.count > 0 && focusedIndex >= 0 ? repeater.itemAt(focusedIndex) : null

    // The sliding "selection" square: a single shared, text-less Rectangle
    // that tracks whichever delegate is currently focused and eases its
    // x/width there, instead of the focused delegate just snapping to an
    // accent fill in place. Declared after `row` (so it paints on top of
    // every delegate's background fill) but before `labels` (so every
    // label still paints on top of *it* — see `labels`' comment for why
    // that split is needed).
    Rectangle {
        id: selection
        visible: root.focusedDelegate !== null
        color: root.theme.accent
        antialiasing: false
        x: root.focusedDelegate ? row.x + root.focusedDelegate.x : 0
        y: root.focusedDelegate ? row.y + root.focusedDelegate.y : 0
        width: root.focusedDelegate ? root.focusedDelegate.width : 0
        height: root.focusedDelegate ? root.focusedDelegate.height : 0

        Behavior on x {
            NumberAnimation {
                duration: root.theme.resizeDuration
                easing.type: root.theme.resizeEasing
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: root.theme.resizeDuration
                easing.type: root.theme.resizeEasing
            }
        }
    }

    // The actual visible labels — one static Text per workspace, positioned
    // to sit exactly over its own (invisible-text) delegate in `row` and
    // never moving on its own. Kept as a separate top layer, painted after
    // `selection`, specifically so a label's fixed position is completely
    // decoupled from the sliding indicator underneath it: earlier this drew
    // the focused workspace's name *inside* `selection` itself, which made
    // the name visibly slide/fly across the bar together with the square —
    // confusing, since a label naming a fixed workspace has no reason to
    // move. Now only the colored square travels; every number stays put and
    // just (instantly) flips to accent/bold once the square finishes
    // sliding under it.
    Repeater {
        model: Hyprland.workspaces

        delegate: Text {
            id: wsLabel
            required property var modelData
            required property int index

            // See focusedDelegate's comment above: reading `repeater.count`
            // here (not just calling itemAt()) is what makes this
            // re-evaluate once the Repeater actually finishes creating this
            // index's item, instead of staying null forever.
            readonly property var bgItem: repeater.count > index ? repeater.itemAt(index) : null

            renderType: Text.NativeRendering
            visible: bgItem ? bgItem.visible : false
            x: bgItem ? row.x + bgItem.x + (bgItem.width - implicitWidth) / 2 : 0
            y: bgItem ? row.y + bgItem.y + (bgItem.height - implicitHeight) / 2 : 0
            text: modelData.name
            color: modelData.focused ? root.theme.accentText : root.theme.workspaceEmptyText
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
            // bgItem is this label's matching wsDelegate — reuse its
            // activeOnThisScreen rather than redoing the monitor check.
            font.bold: modelData.focused || (bgItem && bgItem.activeOnThisScreen)
        }
    }
}
