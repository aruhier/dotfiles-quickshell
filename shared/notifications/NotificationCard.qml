pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.shared
import qs.shared.animations
import qs.shared.notifications
import qs.themes

// One notification's visual, shared by the popup stack (floating: true) and
// the control-center list (floating: false). The caller supplies `width`;
// height follows content.
Item {
    id: card

    required property var wrapper
    // What the card reads. A row's wrapper is live only while listed: the
    // list releases a row later than the service drops its wrapper. A toast
    // reads a snapshot instead (NotificationPopupWindow.qml), never dropped.
    readonly property var w: card.floating || NotificationService.isLive(card.wrapper) ? card.wrapper : card.empty
    readonly property var empty: ({
            "summary": "",
            "body": "",
            "appIcon": "",
            "image": "",
            "timeStr": "",
            "defaultAction": null,
            "otherActions": []
        })
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

    // The card never dismisses anything itself: whoever owns it also owns the
    // exit. A control-centre row decides who plays the gesture — the row
    // whole, or one card of an expanded group — and the toast stack dismisses
    // outright, its exit being staged off the service's list.
    signal dismissRequested

    // Whole-card hover, not just mainColumn's, so the actions row reveals the
    // close button too. Drives the close button's opacity.
    readonly property bool hovered: hoverHandler.hovered

    HoverHandler {
        id: hoverHandler
    }

    // The output this card is on, so the opening can keep its edges on the
    // device pixel grid. Null in the control centre, where the plate is the
    // whole card and every value below is integral already.
    property ShellScreen screen: null

    // The width the plate is open to, and the one thing the toast stack drives:
    // it springs this between `collapsedWidth` and the card's own width, and
    // the rest of the opening follows. The plate rests centred on the card and
    // opens out to it *sideways*, the way the OSD's pill grows out of its own
    // middle, so a notification arrives as its icon alone. Vertically it only
    // grows downwards — see `collapsedY`.
    property real openWidth: width
    // 0..1 across that. Clamped, because the spring deliberately overshoots
    // both ends — a height that followed it there would open into the toast
    // below, and a reveal would flicker at full.
    readonly property real opened: Theme.ramp(openWidth, collapsedWidth, width)

    // The plate around the icon alone: its left inset mirrored on the right,
    // and `padding` above and below.
    readonly property real collapsedWidth: 2 * (padding + iconHorizontalPadding) + iconSize
    readonly property real collapsedHeight: 2 * padding + iconSize
    // Where the plate shrinks onto while the toast is leaving, or < 0 to keep
    // centring it as the opening does. Pinned, the icon under the plate stays
    // put through the whole shut — and the wind-up that follows is then seen
    // at its full size, where a centred collapse drags the icon the other way
    // and cancels most of it. The caller latches this at the moment the exit
    // starts rather than hardcoding 0, so a toast dismissed before it finished
    // opening pins where it already is instead of jumping.
    property real pinnedX: -1
    // Where the collapsed plate sits vertically. The icon is centred in
    // contentRow, which a three-line body pushes taller than the icon itself,
    // so a plate drawn at the card's own top corner would cut it off — this
    // drops the plate to where the icon actually is, which is 0 on all but
    // those. Deliberately *not* centred the way the width is: the content
    // stays put vertically whatever the plate does, and a card sliding up
    // into place under a plate opening around it reads wrong.
    readonly property real collapsedY: Math.max(0, (contentRow.height - iconSize) / 2)

    // The plate's rect. Every edge is snapped, not just the size: the plate
    // carries a 1px border and a corner radius on all four sides, and an edge
    // on half a device pixel renders at half intensity and crawls as it moves.
    // See notes/text.md on the pixel grid.
    readonly property real plateWidth: Screens.snap(openWidth, card.screen)
    readonly property real plateHeight: Screens.snap(collapsedHeight + opened * (height - collapsedHeight), card.screen)
    readonly property real plateX: pinnedX >= 0 ? pinnedX : Screens.snap((width - plateWidth) / 2, card.screen)
    readonly property real plateY: Screens.snap(collapsedY * (1 - opened), card.screen)

    // Everything past the icon, held back to the last quarter of the opening.
    // The reveal is a hard clip edge, so text caught under it is cut mid-glyph
    // and wipes in letter by letter; this keeps it near-transparent until
    // there is almost nothing left to cut.
    readonly property real detailOpacity: Theme.ramp(opened, 0.72, 1)

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
    // Settable: a toast rounds harder than a list card (see popupRadius).
    property int radius: NotificationTheme.cardRadius

    // Split out from `card` so it can be the drop shadow's source.
    Rectangle {
        id: background
        x: card.plateX
        y: card.plateY
        width: card.plateWidth
        height: card.plateHeight
        radius: card.radius
        color: card.floating ? NotificationTheme.bgFloating : NotificationTheme.bg
        // Hidden so the shadow's pass is the only one painting it — see
        // DropShadow.qml. Only for a toast: a control-centre card is over the
        // panel's own plate rather than over the desktop, and undoing the
        // compounding there would lighten every row in the list.
        visible: !card.floating
    }

    DropShadow {
        source: background
    }

    // The content, revealed through the plate rather than laid out inside it:
    // it keeps the card's full size whatever the plate is doing, so no text
    // rewraps and no row reflows on the way open — it only rides the plate's
    // corner. `clip` only while the plate is smaller than the card — a scissor
    // rect, not a layer, so the text under it is not resampled (notes/text.md).
    Item {
        anchors.fill: background
        clip: card.plateWidth < card.width || card.plateHeight < card.height

        Item {
            // Cancels the plate's own offset, so the content sits at the
            // card's coordinates however far down the plate starts. It rides
            // the plate sideways — the clip's x is the plate's — and not at
            // all vertically.
            y: -card.plateY
            width: card.width
            height: card.height

            // Body click invokes the default action; a floating toast also dismisses,
            // a control-center row doesn't (it's a list being browsed). Covers the
            // whole card — later siblings still win the hit-test.
            MouseArea {
                anchors.fill: parent
                enabled: card.interactive && (card.floating || card.w.defaultAction !== null)
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (card.w.defaultAction !== null)
                        card.w.defaultAction.invoke();
                    if (card.floating)
                        card.dismissRequested();
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
                            visible: card.w.image !== ""
                            source: card.w.image
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        IconImage {
                            anchors.fill: parent
                            visible: card.w.image === ""
                            source: Quickshell.iconPath(card.w.appIcon, "dialog-information")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        // Nothing but the icon while the plate is still
                        // opening — the clip alone would sweep half-drawn
                        // words across the card.
                        opacity: card.detailOpacity

                        RowLayout {
                            id: headerRow
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                id: summaryText
                                Layout.fillWidth: true
                                text: card.w.summary
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
                                text: card.w.timeStr
                                color: NotificationTheme.text
                                // Matches the summary beside it.
                                bold: true
                                font.pixelSize: NotificationTheme.fontSize
                            }
                        }

                        StyledText {
                            id: bodyText
                            Layout.fillWidth: true
                            visible: card.w.body !== ""
                            text: card.w.body
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
                opacity: card.detailOpacity
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: mainColumn.bottom
                anchors.topMargin: card.actionsTopMargin
                anchors.leftMargin: card.actionsMargin
                anchors.rightMargin: card.actionsMargin
                visible: card.w.otherActions.length > 0
                spacing: 8

                Repeater {
                    id: actionsRepeater
                    model: card.w.otherActions

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
                            font.pixelSize: NotificationTheme.fontSizeBody
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
                opacity: card.hovered && card.interactive ? card.detailOpacity : 0
                onActivated: card.dismissRequested()
            }
        }
    }

    // A top-most overlay, not the background's `border`: that paints under
    // the children. No mouse handling, so it steals nothing underneath.
    Rectangle {
        anchors.fill: background
        radius: card.radius
        color: "transparent"
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? NotificationTheme.bgSelected : NotificationTheme.borderSubtle
    }
}
