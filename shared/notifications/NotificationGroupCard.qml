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

    // Emitted when the user acts on this row with the mouse, so the list can
    // move the keyboard selection here. The card doesn't know its own index
    // and selection isn't its state to own, hence a signal rather than a
    // write.
    signal selectRequested

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

    // Gap between the expanded group's content and the selection ring drawn
    // around it. Reserved unconditionally (see expandedColumn's margins), so
    // the ring lands on this row's full width — exactly where the collapsed
    // stack's and a single card's own selection border sits.
    readonly property int selectionOutset: 6

    implicitHeight: !isGroup ? singleCard.implicitHeight : (expanded ? expandedColumn.implicitHeight + root.selectionOutset * 2 : collapsedStack.implicitHeight)

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
            onClicked: {
                root.selectRequested();
                NotificationService.setGroupExpanded(root.group.key, true);
            }
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
    ColumnLayout {
        id: expandedColumn
        visible: root.isGroup && root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Inset all round by the selection ring's outset, whether or not this
        // group is the selected one, so moving the selection onto a row never
        // shifts its contents or the rows below it.
        anchors.leftMargin: root.selectionOutset
        anchors.rightMargin: root.selectionOutset
        anchors.topMargin: root.selectionOutset
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
                bold: true
                font.pixelSize: NotificationTheme.fontSize
                elide: Text.ElideRight
            }

            // Collapse button.
            PressableIcon {
                text: "󰅃"
                color: NotificationTheme.text
                font.pixelSize: NotificationTheme.fontSize + 4
                onActivated: {
                    root.selectRequested();
                    NotificationService.setGroupExpanded(root.group.key, false);
                }
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
                // Rows aren't selectable on their own (see the ring below),
                // so selecting the group opens up every row's body.
                showFullBody: root.selected
            }
        }
    }

    // Selection highlight for the group as a whole: individual rows inside it
    // are never keyboard-selectable on their own.
    //
    // Declared last so it paints over expandedColumn, and outset from it on
    // every side. Underneath and flush, as it was, the ring survived only in
    // the gaps between cards: each card's own opaque background and hairline
    // border sit at exactly the same left and right edges and covered the ring
    // wherever a card spanned it, so a selected expanded group read as a
    // dashed outline rather than one box. The outset also keeps the ring clear
    // of the header's collapse and close buttons, which it used to run under.
    Rectangle {
        visible: root.isGroup && root.expanded && root.selected
        anchors.fill: expandedColumn
        anchors.margins: -root.selectionOutset
        radius: NotificationTheme.cardRadius
        color: "transparent"
        border.width: 2
        border.color: NotificationTheme.bgSelected
    }
}
