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
    // Keyboard selection in the control-center list. Floating popups never
    // set this — they have no keyboard focus to select with.
    property bool selected: false

    // swaync's `.notification-default-action` padding stacked on
    // `.notification-content`'s, which the reference screenshot bears out.
    property int padding: 10
    // swaync's --notification-icon-size.
    property int iconSize: 64
    // Breathing room either side of the icon, on top of mainColumn's padding
    // and the row's spacing.
    property int iconHorizontalPadding: 4
    // Inset of the action-button row from the card's edges: swaync's
    // `.notification-alt-actions` padding plus each button's own margin.
    property int actionsMargin: 8
    // The gap above the row is bigger than its side and bottom inset: swaync
    // stacks `.notification-content`'s bottom padding on the action row's.
    property int actionsTopMargin: 16

    // False when this card is the front layer of a collapsed group stack:
    // swaync's group gesture swallows clicks on a collapsed group before they
    // reach the notification, so body/close/action clicks are inert and only
    // the group's own click-to-expand and close-all stay live. Real cards
    // (toasts, control-center rows, expanded-group rows) leave this true.
    property bool interactive: true

    // swaync only reveals the close button on hover of the whole
    // notification, in both contexts. A whole-card HoverHandler, not just the
    // MouseArea over mainColumn, since the actions row should reveal it too.
    property bool hovered: false

    HoverHandler {
        onHoveredChanged: card.hovered = hovered
    }

    // How wide this card needs to be to show its header (summary + time) and
    // action labels unelided — read by NotificationPopupWindow.qml to grow the
    // popup stack past its minimum. Ignores body text on purpose: that wraps,
    // so a long paragraph should fill more lines rather than stretch the toast,
    // unlike a single-line summary or action label, which would get clipped.
    readonly property real headerNaturalWidth: summaryText.implicitWidth + (timeText.visible ? headerRow.spacing + timeText.implicitWidth : 0)
    readonly property real actionsNaturalWidth: {
        if (!actionsRow.visible)
            return 0;
        // Widest label times the button count: every button renders at the
        // same width (see actionButton's Layout.preferredWidth), so the longest
        // label decides how wide they all are. Plus the row's own inset.
        let widest = 0;
        for (let i = 0; i < actionsRepeater.count; i++) {
            const item = actionsRepeater.itemAt(i);
            if (item)
                widest = Math.max(widest, item.implicitWidth);
        }
        return widest * actionsRepeater.count + actionsRow.spacing * Math.max(0, actionsRepeater.count - 1) + card.actionsMargin * 2;
    }
    readonly property real naturalWidth: Math.max(card.padding * 2 + card.iconSize + card.iconHorizontalPadding * 2 + contentRow.spacing + headerNaturalWidth, actionsNaturalWidth)

    // actionsRow is inset from the card's edges, so it needs a top and a
    // matching bottom gap on top of its own height. When hidden, the card
    // falls back to plain `padding` on the bottom, like the top.
    implicitHeight: padding + mainColumn.implicitHeight + (actionsRow.visible ? actionsTopMargin + actionsRow.height + actionsMargin : padding)

    // A property rather than inlined at each site, since the selection-border
    // overlay has to match the background's shape.
    readonly property int radius: NotificationTheme.cardRadius

    // The card's fill, split out from `card` (an Item, not a Rectangle) so it
    // can be a MultiEffect source for swaync's `.notification` box-shadow. An
    // Item used as a MultiEffect `source` is automatically excluded from normal
    // scene painting, so this never double-renders.
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

    // Body click invokes the default action if the sender declared one.
    // Floating popups also dismiss on any body click: a toast is transient and
    // click-to-acknowledge is the usual convention, whereas control-center
    // rows are a list being browsed and only dismiss via the close button or
    // Delete key. Covers the whole card — actionsRow and the close button are
    // declared later in the tree, so they still win the hit-test.
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
                // Centered against the whole text column, matching swaync's
                // GTK box. This row holds all of the card's content, so
                // centering within it achieves that.
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
                // Summary text box bottom to body text box top, measured off
                // the reference screenshot.
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
                        font.bold: true
                        font.pixelSize: NotificationTheme.fontSize
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: timeText
                        // swaync only sets the time on control-center
                        // entries; a toast's label is never populated.
                        visible: !card.floating
                        text: card.wrapper.timeStr
                        color: NotificationTheme.text
                        // `.time` reuses --font-size-summary and is bold, the
                        // same as `.summary` beside it.
                        font.bold: true
                        font.pixelSize: NotificationTheme.fontSize
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: card.wrapper.body !== ""
                    text: card.wrapper.body
                    color: NotificationTheme.text
                    font.pixelSize: NotificationTheme.fontSizeBody
                    // Pango leads Inter more generously than Qt: ~21.25px
                    // against Qt's ~19.4px at this size, so wrapped bodies
                    // would otherwise read visibly tighter than swaync's.
                    lineHeight: 1.1
                    lineHeightMode: Text.ProportionalHeight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Individually rounded button chips inset from the card's edges, matching
    // swaync: each action is its own bordered rectangle with a visible fill at
    // rest, not a flush full-width bar split by a hairline.
    RowLayout {
        id: actionsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: mainColumn.bottom
        anchors.topMargin: card.actionsTopMargin
        anchors.leftMargin: card.actionsMargin
        anchors.rightMargin: card.actionsMargin
        visible: card.wrapper.otherActions.length > 0
        // Two adjacent buttons' own `.notification-action` margins.
        spacing: 8

        Repeater {
            id: actionsRepeater
            model: card.wrapper.otherActions

            Rectangle {
                id: actionButton
                required property var modelData
                required property int index

                Layout.fillWidth: true
                // Equal preferred widths, so the row splits evenly and every
                // button ends up the same width whatever its label — swaync's
                // are equal too. Without this, fillWidth would only share the
                // *leftover* space and size each button around its own label.
                Layout.preferredWidth: 1
                // A GTK button's height around its label, measured off the
                // reference screenshot.
                Layout.preferredHeight: 36
                // Not used for layout (the Layout.preferred* above win), only
                // read by card.naturalWidth as this button's unsquished
                // minimum.
                implicitWidth: actionLabel.implicitWidth + 16
                // swaync's `.text-button` radius: tighter than the card's own,
                // which is what makes these read as buttons rather than pills.
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
                    // ExtraBold, not plain bold: swaync's labels render
                    // through GTK's bold face, heavier than Inter Variable at
                    // 700 (measured: 5.6px stroke against 3.9px here). By
                    // styleName rather than font.weight, since Qt won't pick a
                    // face past 700 off this variable font by weight alone but
                    // does honour the named instance fontconfig exposes.
                    font.styleName: "ExtraBold"
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

    // Close button pinned to the top-right corner rather than sharing the
    // header row's horizontal space with the summary and time. Declared after
    // mainColumn/actionsRow so it sits on top and wins the hit-test over the
    // whole-card click-to-dismiss MouseArea.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: 24
        height: 24
        radius: 12
        color: NotificationTheme.bgHover
        opacity: card.hovered && card.interactive ? 1 : 0
        scale: closePress.value

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        PressSpring {
            id: closePress
            pressed: closeArea.pressed
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            enabled: card.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationService.dismiss(card.wrapper)
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            visible: closeArea.containsMouse
            color: Theme.accent
        }

        StyledText {
            anchors.centerIn: parent
            text: "✕"
            color: closeArea.containsMouse ? "black" : NotificationTheme.text
            font.pixelSize: 12
        }
    }

    // The selection border is its own top-most overlay rather than the
    // background's `border`, which paints underneath children and would sit
    // below the opaque content instead of outlining the card. It has no mouse
    // handling, so it steals nothing from the MouseAreas underneath.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? NotificationTheme.bgSelected : Qt.rgba(NotificationTheme.text.r, NotificationTheme.text.g, NotificationTheme.text.b, 0.1)
    }
}
