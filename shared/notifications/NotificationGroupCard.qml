pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.shared
import qs.services
import qs.shared.notifications

// One row of the control-center list: a per-app group, mirroring swaync's
// notification-grouping. A group of one renders as a plain NotificationCard;
// 2+ collapse into a peeking card-stack that expands on click into a header
// (app icon/name, collapse, close-all) plus the individual cards. Floating
// popups never group this way and use NotificationCard directly.
Item {
    id: root

    required property var group
    property bool selected: false

    readonly property int count: group.items.length
    readonly property bool isGroup: count > 1
    // notificationGroups walks a newest-first list and appends same-app
    // entries as it finds them, so items[0] is always the group's most recent
    // notification — what the header and single-item view key off.
    readonly property var latest: group.items[0]
    readonly property bool expanded: root.isGroup && NotificationService.isGroupExpanded(root.group.key)

    // swaync's NUM_STACKED_NOTIFICATIONS: the front card plus up to 2
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
                // Named depth, not "layer": that shadows QQuickItem's own
                // layer-effect property.
                readonly property int depth: root.peekCount - index

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: peekLayer.depth * 8
                anchors.rightMargin: peekLayer.depth * 8
                y: peekLayer.depth * root.peekOffset
                height: frontCard.implicitHeight
                radius: NotificationTheme.cardRadius
                // Not the front card's own fill, which is near tone-on-tone
                // with the panel behind it: bgHover makes the peeking edges
                // read as stacked cards rather than disappear into the panel.
                color: NotificationTheme.bgHover
                border.width: 1
                border.color: NotificationTheme.borderSubtle
            }
        }

        NotificationCard {
            id: frontCard
            anchors.left: parent.left
            anchors.right: parent.right
            wrapper: root.latest
            floating: false
            selected: root.selected
            // Body/close/action clicks are inert while collapsed — see
            // NotificationCard.qml's `interactive`.
            interactive: false
        }

        // Click anywhere on the stack to expand it. Declared above the
        // close-all button so that button still wins the hit-test.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationService.setGroupExpanded(root.group.key, true)
        }

        // Close-all, revealed on hover like swaync's.
        CloseButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            opacity: collapsedStack.hovered ? 1 : 0
            onActivated: NotificationService.dismissGroup(root.group)
        }
    }

    // ---- 2+, expanded: header + every individual card ----
    // Selection highlight for the group as a whole: individual rows inside it
    // are never keyboard-selectable on their own.
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

            StyledText {
                Layout.fillWidth: true
                text: root.latest.appName
                color: NotificationTheme.text
                font.bold: true
                font.pixelSize: NotificationTheme.fontSize
                elide: Text.ElideRight
            }

            // Collapse button.
            PressableIcon {
                text: "󰅃"
                color: NotificationTheme.text
                font.pixelSize: NotificationTheme.fontSize + 4
                onActivated: NotificationService.setGroupExpanded(root.group.key, false)
            }

            CloseButton {
                onActivated: NotificationService.dismissGroup(root.group)
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
