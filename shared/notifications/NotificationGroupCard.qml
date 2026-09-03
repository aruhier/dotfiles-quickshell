import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../../services"
import "../animations"

// One row of NotificationCenterPanel.qml's list: a control-center-only
// per-app group, mirroring swaync's notification-grouping (default on —
// configSchema.json's notification-grouping defaults true and this repo's
// config.json doesn't override it). A group with one notification renders
// as a plain NotificationCard; 2+ collapse into a peeking card-stack that
// expands, on click, into a header (app icon/name + collapse/close-all) plus
// the individual cards — ported from SwayNotificationCenter's
// notificationGroup/{notificationGroup,expandableGroup}.vala (vendored under
// ~/git/github/SwayNotificationCenter). Floating popups never group this
// way — NotificationPopupWindow.qml keeps using NotificationCard directly.
Item {
    id: root

    required property var group
    property bool selected: false

    readonly property int count: group.items.length
    readonly property bool isGroup: count > 1
    // notificationGroups builds each group by walking `notifications`
    // (newest-first) and appending same-app entries as they're found, so
    // items[0] is always that group's most recent notification — matches
    // swaync's get_latest_notification()/set_icon(), which the header and
    // single-item view below key off of.
    readonly property var latest: group.items[0]
    readonly property bool expanded: root.isGroup && NotificationService.isGroupExpanded(root.group.key)

    // ExpandableGroup.NUM_STACKED_NOTIFICATIONS: the front card plus up to 2
    // peeking behind it.
    readonly property int peekCount: Math.min(count - 1, 2)
    readonly property int peekOffset: 6

    implicitHeight: !isGroup ? singleCard.implicitHeight : (expanded ? expandedColumn.implicitHeight : collapsedStack.implicitHeight)

    // ---- single notification: no group chrome at all ----
    NotificationCard {
        id: singleCard
        visible: !root.isGroup
        anchors.left: parent.left
        anchors.right: parent.right
        wrapper: root.latest
        floating: false
        selected: root.selected
    }

    // ---- 2+: collapsed card-stack ----
    Item {
        id: collapsedStack
        visible: root.isGroup && !root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: frontCard.implicitHeight + root.peekOffset * root.peekCount

        property bool hovered: false
        HoverHandler {
            onHoveredChanged: collapsedStack.hovered = hovered
        }

        // Peeking layers behind the front card, furthest-back first so the
        // front card paints over them.
        Repeater {
            model: root.peekCount

            Rectangle {
                id: peekLayer
                required property int index
                // Named depth, not "layer" — that shadows QQuickItem's own
                // built-in `layer` (layer-effect) property.
                readonly property int depth: root.peekCount - index

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: peekLayer.depth * 8
                anchors.rightMargin: peekLayer.depth * 8
                y: peekLayer.depth * root.peekOffset
                height: frontCard.implicitHeight
                radius: NotificationTheme.cardRadius
                // NotificationTheme.bg (the front card's own fill) reads as
                // near-invisible here — it's almost tone-on-tone with the
                // panel's own bgGlobal behind it. bgHover instead, so the
                // peeking edges actually read as cards stacked behind the
                // front one rather than disappearing into the panel.
                color: NotificationTheme.bgHover
                border.width: 1
                border.color: Qt.rgba(NotificationTheme.text.r, NotificationTheme.text.g, NotificationTheme.text.b, 0.1)
            }
        }

        NotificationCard {
            id: frontCard
            anchors.left: parent.left
            anchors.right: parent.right
            wrapper: root.latest
            floating: false
            selected: root.selected
            // The real notification's own body/close/action clicks are
            // inert while collapsed — see NotificationCard.qml's
            // `interactive` doc comment.
            interactive: false
        }

        // Click anywhere on the stack expands it — matches
        // notificationGroup.vala's gesture handler (only reachable here
        // since isGroup guarantees swaync's MANY state). Declared above the
        // close-all button below so that button still wins the hit-test.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationService.setGroupExpanded(root.group.key, true)
        }

        // Close-all — swaync only reveals this on hover of a collapsed MANY
        // group (notificationGroup.vala's motion_controller).
        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            color: "black"
            opacity: collapsedStack.hovered ? 1 : 0
            scale: closeAllPress.value

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            PressSpring {
                id: closeAllPress
                pressed: closeAllArea.pressed
            }

            MouseArea {
                id: closeAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationService.dismissGroup(root.group)
            }

            Rectangle {
                anchors.fill: parent
                radius: 9
                visible: closeAllArea.containsMouse
                color: "#1e1e1e"
            }

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: "✕"
                color: NotificationTheme.text
                font.pixelSize: 10
            }
        }
    }

    // ---- 2+, expanded: header + every individual card ----
    // Selection highlight for the whole expanded group — individual rows
    // inside it are never themselves keyboard-selectable, only the group
    // row as a whole (see NotificationCenterPanel.qml's focusScope).
    Rectangle {
        visible: root.isGroup && root.expanded && root.selected
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: expandedColumn.top
        anchors.bottom: expandedColumn.bottom
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        radius: NotificationTheme.cardRadius
        color: "transparent"
        border.width: 2
        border.color: NotificationTheme.bgSelected
    }

    ColumnLayout {
        id: expandedColumn
        visible: root.isGroup && root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            IconImage {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                source: Quickshell.iconPath(root.latest.appIcon, "dialog-information")
            }

            Text {
                renderType: Text.NativeRendering
                Layout.fillWidth: true
                text: root.latest.appName
                color: NotificationTheme.text
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: NotificationTheme.fontSize
                elide: Text.ElideRight
            }

            // Collapse button.
            Text {
                renderType: Text.NativeRendering
                text: "󰅃"
                color: NotificationTheme.text
                font.family: Theme.fontFamily
                font.pixelSize: NotificationTheme.fontSize + 4
                scale: collapsePress.value

                PressSpring {
                    id: collapsePress
                    pressed: collapseArea.pressed
                }

                MouseArea {
                    id: collapseArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.setGroupExpanded(root.group.key, false)
                }
            }

            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 9
                color: "black"
                scale: expandedCloseAllPress.value

                PressSpring {
                    id: expandedCloseAllPress
                    pressed: expandedCloseAllArea.pressed
                }

                MouseArea {
                    id: expandedCloseAllArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.dismissGroup(root.group)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    visible: expandedCloseAllArea.containsMouse
                    color: "#1e1e1e"
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "✕"
                    color: NotificationTheme.text
                    font.pixelSize: 10
                }
            }
        }

        Repeater {
            model: root.group.items

            NotificationCard {
                id: groupItemCard
                required property var modelData
                Layout.fillWidth: true
                wrapper: groupItemCard.modelData
                floating: false
            }
        }
    }
}
