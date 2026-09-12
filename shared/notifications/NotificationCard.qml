pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.shared
import qs.services
import qs.shared.animations
import qs.shared.notifications

// One notification's visual, shared by the popup stack (floating: true) and
// the control-center list (floating: false). The caller supplies `width`;
// height follows content.
Item {
    id: card

    required property var wrapper
    property bool floating: false
    // Keyboard selection in the control-center list; never set on popups.
    property bool selected: false
    // Lifts the body's line cap. Follows `selected`, but an expanded group
    // overrides it for rows that are never selected individually.
    property bool showFullBody: selected

    property int padding: 10
    property int iconSize: 64
    // On top of mainColumn's padding and the row's spacing.
    property int iconHorizontalPadding: 4
    // Inset of the action row from the card's edges.
    property int actionsMargin: 8
    // Deliberately bigger than the side inset, to separate the actions from
    // the message above them.
    property int actionsTopMargin: 16

    // False for the front layer of a collapsed group stack: a click there
    // belongs to the group (expand / close-all), not to this notification.
    property bool interactive: true

    // Whole-card hover, not just mainColumn's, so the actions row reveals the
    // close button too. Drives the close button's opacity.
    property bool hovered: false

    HoverHandler {
        onHoveredChanged: card.hovered = hovered
    }

    // Width needed to show header, body and actions unwrapped, read by
    // NotificationPopupWindow.qml to grow the stack (clamped to popupMaxWidth
    // there, so an over-long body just pegs the toast at its maximum).
    readonly property real headerNaturalWidth: summaryText.implicitWidth + (timeText.visible ? headerRow.spacing + timeText.implicitWidth : 0)
    // A wrapping Text reports its *unwrapped* width as implicitWidth.
    readonly property real bodyNaturalWidth: bodyText.visible ? bodyText.implicitWidth : 0
    readonly property real actionsNaturalWidth: {
        if (!actionsRow.visible)
            return 0;
        // Every button renders at the same width (see actionButton's
        // Layout.preferredWidth), so the widest label decides all of them.
        let widest = 0;
        for (let i = 0; i < actionsRepeater.count; i++) {
            const item = actionsRepeater.itemAt(i);
            if (item)
                widest = Math.max(widest, item.implicitWidth);
        }
        return widest * actionsRepeater.count + actionsRow.spacing * Math.max(0, actionsRepeater.count - 1) + card.actionsMargin * 2;
    }
    // The text column has to fit whichever of its two rows is wider.
    readonly property real naturalWidth: Math.max(card.padding * 2 + card.iconSize + card.iconHorizontalPadding * 2 + contentRow.spacing + Math.max(headerNaturalWidth, bodyNaturalWidth), actionsNaturalWidth)

    // actionsRow is inset, so it adds a top and matching bottom gap; hidden,
    // the bottom falls back to plain `padding`.
    implicitHeight: padding + mainColumn.implicitHeight + (actionsRow.visible ? actionsTopMargin + actionsRow.height + actionsMargin : padding)

    // Shared so the selection-border overlay matches the background's shape.
    readonly property int radius: NotificationTheme.cardRadius

    // Split out from `card` so it can be the MultiEffect source for the drop
    // shadow. A source Item is excluded from normal scene painting, so this
    // never double-renders.
    Rectangle {
        id: background
        anchors.fill: parent
        radius: card.radius
        color: card.floating ? NotificationTheme.bgFloating : NotificationTheme.bg
    }

    MultiEffect {
        anchors.fill: background
        source: background
        shadowEnabled: true
        shadowColor: "black"
        shadowOpacity: 0.4
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 1
        shadowBlur: 0.4
    }

    // Body click invokes the default action; a floating toast also dismisses,
    // a control-center row doesn't (it's a list being browsed). Covers the
    // whole card — later siblings still win the hit-test.
    MouseArea {
        anchors.fill: parent
        enabled: card.interactive && (card.floating || card.wrapper.defaultAction !== null)
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (card.wrapper.defaultAction !== null)
                card.wrapper.defaultAction.invoke();
            if (card.floating)
                NotificationService.dismiss(card.wrapper);
        }
    }

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.padding
        spacing: 6

        RowLayout {
            id: contentRow
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.preferredWidth: card.iconSize
                Layout.preferredHeight: card.iconSize
                Layout.leftMargin: card.iconHorizontalPadding
                Layout.rightMargin: card.iconHorizontalPadding
                // Centered against the whole text column.
                Layout.alignment: Qt.AlignVCenter

                Image {
                    anchors.fill: parent
                    visible: card.wrapper.image !== ""
                    source: card.wrapper.image
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                IconImage {
                    anchors.fill: parent
                    visible: card.wrapper.image === ""
                    source: Quickshell.iconPath(card.wrapper.appIcon, "dialog-information")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        id: summaryText
                        Layout.fillWidth: true
                        text: card.wrapper.summary
                        color: NotificationTheme.text
                        bold: true
                        font.pixelSize: NotificationTheme.fontSize
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: timeText
                        // Control-center rows only: a toast is current by
                        // definition, so its time says nothing.
                        visible: !card.floating
                        text: card.wrapper.timeStr
                        color: NotificationTheme.text
                        // Matches the summary beside it.
                        bold: true
                        font.pixelSize: NotificationTheme.fontSize
                    }
                }

                StyledText {
                    id: bodyText
                    Layout.fillWidth: true
                    visible: card.wrapper.body !== ""
                    text: card.wrapper.body
                    color: NotificationTheme.text
                    font.pixelSize: NotificationTheme.fontSizeBody
                    // Qt leads Inter tightly (~19.4px at this size); wrapped
                    // bodies need the extra air to stay readable.
                    lineHeight: 1.1
                    lineHeightMode: Text.ProportionalHeight
                    wrapMode: Text.WordWrap
                    // Capped so one long message can't dominate the list; the
                    // cap lifts on selection. Text has no "unlimited" value, so
                    // 1000 stands in for it.
                    maximumLineCount: card.showFullBody ? 1000 : 5
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Individually rounded chips, not a flush full-width bar split by a
    // hairline, so each action reads as its own button.
    RowLayout {
        id: actionsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: mainColumn.bottom
        anchors.topMargin: card.actionsTopMargin
        anchors.leftMargin: card.actionsMargin
        anchors.rightMargin: card.actionsMargin
        visible: card.wrapper.otherActions.length > 0
        spacing: 8

        Repeater {
            id: actionsRepeater
            model: card.wrapper.otherActions

            Rectangle {
                id: actionButton
                required property var modelData
                required property int index

                Layout.fillWidth: true
                // Equal preferred widths so the row splits evenly; fillWidth
                // alone would only share the leftover space and size each
                // button around its own label.
                Layout.preferredWidth: 1
                Layout.preferredHeight: 36
                // Not used for layout — read by card.naturalWidth as this
                // button's unsquished minimum.
                implicitWidth: actionLabel.implicitWidth + 16
                // Tighter than the card's radius, so these read as buttons
                // rather than pills.
                radius: 6
                color: actionArea.containsMouse ? NotificationTheme.bgHover : NotificationTheme.bgButton
                border.width: 1
                border.color: NotificationTheme.borderNotification
                scale: actionPress.value

                PressSpring {
                    id: actionPress
                    pressed: actionArea.pressed
                }

                StyledText {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: actionButton.modelData.text
                    color: NotificationTheme.text
                    // Heavier than `bold` (700) on purpose, so a small label
                    // on a busy card still reads as the actionable thing. Must
                    // go through the wght axis — StyledText's axis silently
                    // overrides font.styleName.
                    wght: 800
                    font.pixelSize: NotificationTheme.fontSizeAction
                }

                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    enabled: card.interactive
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: actionButton.modelData.invoke()
                }
            }
        }
    }

    // Pinned to the corner rather than sharing the header row's space.
    // Declared last so it wins the hit-test over the card-wide MouseArea.
    CloseButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        diameter: 24
        // Bigger and lighter than the group's close-all — this is the card's
        // own affordance, not a secondary bulk action.
        restColor: NotificationTheme.bgHover
        // A pixel under the ratio, tuned before this was shared.
        glyphSize: 12
        interactive: card.interactive
        opacity: card.hovered && card.interactive ? 1 : 0
        onActivated: NotificationService.dismiss(card.wrapper)
    }

    // A top-most overlay, not the background's `border`: that paints under
    // the children. No mouse handling, so it steals nothing underneath.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? NotificationTheme.bgSelected : NotificationTheme.borderSubtle
    }
}
