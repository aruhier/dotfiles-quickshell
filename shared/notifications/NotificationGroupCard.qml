pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.shared
import qs.services
import qs.shared.notifications
import qs.themes

// One row of the control-center list: a per-app group. A group of one renders
// as a plain NotificationCard; 2+ collapse into a peeking card-stack that
// expands on click into a header (app icon/name, collapse, close-all) plus the
// individual cards. Popups never group, and use NotificationCard directly.
Item {
    id: root

    required property var group
    property bool selected: false

    // Mouse action on this row, so the list can move the keyboard selection
    // here — the card knows neither its index nor who owns the selection.
    signal selectRequested

    readonly property int count: group.items.length
    readonly property bool isGroup: count > 1
    // items[0] is always the group's newest — notificationGroups builds each
    // group in newest-first order.
    readonly property var latest: group.items[0]
    readonly property bool expanded: root.isGroup && NotificationService.isGroupExpanded(root.group.key)

    // The front card plus up to 2 peeking behind it.
    readonly property int peekCount: Math.min(count - 1, 2)
    readonly property int peekOffset: 6

    // Gap between an expanded group's content and its selection ring.
    // Reserved unconditionally (see expandedColumn's margins), so the ring
    // lands where a collapsed stack's or single card's border would.
    readonly property int selectionOutset: 6

    implicitHeight: !isGroup ? singleCard.implicitHeight : (expanded ? expandedColumn.implicitHeight + root.selectionOutset * 2 : collapsedStack.implicitHeight)

    // A dismissal here is deferred to an exit gesture: the row winds up left,
    // slides off the panel's edge, and only then does the notification
    // actually go. It has to be that way round — the list's model is a plain
    // array, so any change to it recreates every delegate mid-flight.
    readonly property alias exiting: rowExit.active
    // Enough to put a leaving row past the list's clip, which is what it
    // actually disappears behind — 16px short of the screen edge, the panel's
    // own padding. Nothing is drawn in that strip, so the cut doesn't read.
    readonly property real exitTravel: width + NotificationTheme.listPadding + NotificationTheme.panelPadding

    // Every path that dismisses the row as a whole: its close-all buttons, a
    // single-notification row's own close button, and the panel's Delete key.
    function dismiss() {
        rowExit.start();
    }

    // Nothing left to click on a row that is leaving, the way a closing toast
    // goes inert.
    enabled: !root.exiting

    transform: Translate {
        x: rowExit.value
    }

    DismissSlide {
        id: rowExit
        travel: root.exitTravel
        onFinished: NotificationService.dismissLater(root.group.items)
    }

    // A model reset under the gesture — a notification arriving mid-exit —
    // destroys this delegate; the click still has to land.
    Component.onDestruction: if (rowExit.active)
        NotificationService.dismissLater(root.group.items)

    // ---- single notification: no group chrome at all ----
    NotificationCard {
        id: singleCard
        visible: !root.isGroup
        anchors.left: parent.left
        anchors.right: parent.right
        wrapper: root.latest
        floating: false
        selected: root.selected
        // The card *is* the row here, so its close button leaves as one.
        onDismissRequested: root.dismiss()
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

        // Furthest-back first, so the front card paints over them.
        Repeater {
            model: root.peekCount

            Rectangle {
                id: peekLayer
                required property int index
                // Not "layer" — that shadows QQuickItem's layer-effect.
                readonly property int depth: root.peekCount - index
                // How far each layer behind the front card is inset, so its
                // edge peeks out on both sides.
                readonly property int inset: peekLayer.depth * 8

                // Sized off `collapsedStack` rather than anchored through
                // `parent`: a Repeater delegate is created before it is
                // parented, so an anchor reading `parent.left` resolves
                // against null and logs a TypeError for every layer, on every
                // rebuild.
                x: peekLayer.inset
                width: collapsedStack.width - peekLayer.inset * 2
                y: peekLayer.depth * root.peekOffset
                height: frontCard.implicitHeight
                radius: NotificationTheme.cardRadius
                // Lighter than the front card's fill, which is near
                // tone-on-tone with the panel — otherwise the peeking edges
                // disappear instead of reading as a stack.
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

        // Click anywhere to expand. Declared before the close-all button so
        // that button still wins the hit-test.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.selectRequested();
                NotificationService.setGroupExpanded(root.group.key, true);
            }
        }

        // Close-all, revealed on hover.
        CloseButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            opacity: collapsedStack.hovered ? 1 : 0
            onActivated: root.dismiss()
        }
    }

    // ---- 2+, expanded: header + every individual card ----
    ColumnLayout {
        id: expandedColumn
        visible: root.isGroup && root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Inset by the ring's outset even when unselected, so moving the
        // selection onto a row never shifts it or the rows below.
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
                onActivated: root.dismiss()
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
                // One card of an expanded group leaves on its own; the rest of
                // the group stays put. Only a close-all slides the whole row.
                enabled: !cardExit.active
                onDismissRequested: cardExit.start()

                transform: Translate {
                    x: cardExit.value
                }

                DismissSlide {
                    id: cardExit
                    travel: root.exitTravel
                    onFinished: NotificationService.dismissLater([groupItemCard.modelData])
                }

                Component.onDestruction: if (cardExit.active)
                    NotificationService.dismissLater([groupItemCard.modelData])
            }
        }
    }

    // Highlights the group as a whole; rows inside it are never selectable on
    // their own. Declared last and outset on every side: flush and underneath,
    // each card's opaque background covers the ring wherever it spans, leaving
    // a dashed outline, and the ring runs under the header's buttons.
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
