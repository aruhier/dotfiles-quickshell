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
                Layout.preferredWidth: isSpecial ? 0 : Math.round(Math.max(label.implicitWidth + 18, 34))
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

                // Invisible — only exists to size Layout.preferredWidth. The
                // real label lives in the separate `labels` Repeater below,
                // since a sibling can't paint above this delegate's fill but
                // below another delegate's text for many delegates at once.
                Text {
                    id: label
                    visible: false
                    text: modelData.name
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

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
        // workspaces. row.x (added below, unanimated) is deliberately kept
        // out of this spring: row.x already eases smoothly on its own via
        // root's implicitWidth spring + anchors.centerIn, so re-adding it
        // straight through every frame keeps this glued to row's real
        // position instead of chasing it with a second, independent spring
        // — that double-spring is what visibly fought the pill's own
        // resize when a workspace was created and focused at once.
        property real focusedLocalX: root.focusedDelegate ? root.focusedDelegate.x : 0
        Behavior on focusedLocalX {
            SpringAnimation {
                spring: Theme.springSpring
                damping: Theme.springDamping
                epsilon: Theme.springEpsilon
            }
        }

        x: row.x + focusedLocalX
        y: root.focusedDelegate ? row.y + root.focusedDelegate.y : 0
        width: root.focusedDelegate ? root.focusedDelegate.width : 0
        height: root.focusedDelegate ? root.focusedDelegate.height : 0

        Behavior on width {
            SpringAnimation {
                spring: Theme.workspaceSpringSpring
                damping: Theme.workspaceSpringDamping
                epsilon: Theme.springEpsilon
            }
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

    // Static top layer of visible labels, positioned over their matching
    // delegate but never moving themselves — only `selection` slides.
    Repeater {
        model: Hyprland.workspaces

        delegate: Text {
            id: wsLabel
            required property var modelData
            required property int index

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
}
