import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import ".."
import "../../services"
import "../animations"

// One notification's visual — reused by both the popup stack
// (NotificationPopupWindow.qml, floating: true) and the control-center list
// (NotificationCenterPanel.qml, floating: false). Caller supplies `width`;
// height follows content via implicitHeight.
Item {
    id: card

    required property var wrapper
    property bool floating: false
    // Keyboard selection in NotificationCenterPanel's list — floating
    // popups never set this, they have no keyboard focus to select with.
    property bool selected: false

    // 6/64, not the original 8/40 — matches swaync's actual built-in
    // defaults (data/style/style.scss: notification-background padding:
    // 6px 12px, --notification-icon-size: 64px; not overridden by this
    // user's ~/.config/swaync/style.css, which only recolors), confirmed
    // against a live swaync screenshot
    // (~/tmp/screenshots/swaync-notification-popup-cropped.png) showing a
    // large, vertically-centered icon rather than the small top-aligned one
    // this used to render.
    property int padding: 6
    property int iconSize: 64
    // Breathing room to either side of the icon — between it and the card
    // edge on the left, and between it and the summary/body text on the
    // right (on top of mainColumn's own padding and the row's spacing).
    property int iconHorizontalPadding: 4
    // Inset of the action-button row from the card's edges — wider than
    // `padding` because swaync's buttons carry their own `.notification-action
    // { padding: 4px }` on top of the card's content padding. Measured off the
    // reference screenshot (~/tmp/swaync-screenshot.png): 12px there, and that
    // image is ~1.36x scale — its buttons' corners measure ~7.5px against the
    // 6px `border-radius` swaync's own style.css declares, which is what pins
    // the factor down — so ~9 logical px.
    property int actionsMargin: 9
    // The gap above the row is bigger than its side/bottom inset — swaync
    // stacks `.notification-content`'s own bottom padding on top of the action
    // row's, and the reference screenshot bears that out: ~24 logical px from
    // the last line of body text down to the top of the buttons, against the
    // ~9 beside and below them.
    property int actionsTopMargin: 19

    // False when this card is rendered as the peeking front layer of a
    // collapsed NotificationGroupCard stack — swaync's group gesture
    // (notificationGroup.vala, CAPTURE phase + exclusive) swallows clicks on
    // a collapsed MANY group before they reach the individual notification,
    // so body/close/action clicks are inert there; only the group's own
    // click-to-expand and close-all stay live. Real, focus-scoped cards
    // (popup toasts, control-center rows, expanded-group rows) leave this
    // at the default true.
    property bool interactive: true

    // Mirrors notification.ui's close_revealer: swaync only reveals the
    // close button on hover of the whole notification (event_box's
    // enter/leave_notify_event), in both the popup and control-center
    // contexts — confirmed via a live screenshot of the popup showing no
    // close button at rest. Whole-card HoverHandler, not just the
    // MouseArea over mainColumn, since the actions row should reveal it
    // too.
    property bool hovered: false

    HoverHandler {
        onHoveredChanged: card.hovered = hovered
    }

    // How wide this card would need to be to show its header (summary +
    // time) and its action-button labels without eliding/squishing them —
    // read by NotificationPopupWindow.qml to size the popup stack up from
    // its usual minimum when a toast's content actually needs it. Ignores
    // body text on purpose: it wraps (see the body Text's wrapMode below),
    // so a long paragraph should fill more lines rather than stretch the
    // toast wider, unlike a long single-line summary or action label, which
    // would otherwise just get clipped.
    readonly property real headerNaturalWidth: summaryText.implicitWidth + (timeText.visible ? headerRow.spacing + timeText.implicitWidth : 0)
    readonly property real actionsNaturalWidth: {
        if (!actionsRow.visible)
            return 0;
        // Widest label, times the button count — every button renders at the
        // same width (see actionButton's Layout.preferredWidth below), so the
        // longest label is what decides how wide they all have to be. Plus the
        // row's own left/right inset from the card edges, since the buttons no
        // longer span the card's full width.
        let widest = 0;
        for (let i = 0; i < actionsRepeater.count; i++) {
            const item = actionsRepeater.itemAt(i);
            if (item)
                widest = Math.max(widest, item.implicitWidth);
        }
        return widest * actionsRepeater.count + actionsRow.spacing * Math.max(0, actionsRepeater.count - 1) + card.actionsMargin * 2;
    }
    readonly property real naturalWidth: Math.max(card.padding * 2 + card.iconSize + card.iconHorizontalPadding * 2 + contentRow.spacing + headerNaturalWidth, actionsNaturalWidth)

    // actionsRow sits inset from the card's edges now (individually rounded
    // button chips, not a flush bottom bar — see actionsRow below), so it
    // needs its own top gap plus a matching bottom gap on top of its own
    // height, unlike the old flush design this replaced. When it's hidden the
    // card falls back to plain `padding` on the bottom like the top.
    implicitHeight: padding + mainColumn.implicitHeight + (actionsRow.visible ? actionsTopMargin + actionsRow.height + actionsMargin : padding)

    // Kept as a property (rather than inlining NotificationTheme.cardRadius
    // at each call site below) since actionButton's per-corner radii and the
    // selection-border overlay both need to match the background's shape.
    readonly property int radius: NotificationTheme.cardRadius

    // The card's visual fill, pulled out from `card` itself (an Item, not a
    // Rectangle) so it can be used as a MultiEffect source below — matching
    // swaync's `.notification { box-shadow: 0px 1px 12px 1px rgba(0, 0, 0,
    // 0.4) }` (~/dotfiles/swaync/style.css). An Item used as a MultiEffect
    // `source` is automatically excluded from normal scene painting (see
    // Qt's own QtQuick.Controls.FluentWinUI3 ToolTip.qml background, which
    // uses the identical pattern), so this never double-renders.
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

    // Body click invokes the default action, if the sender declared one —
    // matches swaync's notification.vala click_default_action(). Floating
    // popups also dismiss on any body click regardless of a default action
    // (by request) — a toast is transient and "click to acknowledge/take it
    // away" is the common desktop convention, whereas control-center rows
    // are a persisted list the user is browsing and only dismiss via the
    // close button or Delete key. Covers the whole card, not just
    // mainColumn — actionsRow's buttons and the close button below are
    // declared after this in the tree, so they still win the hit-test over
    // their own areas.
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
                // Vertically centered against the whole card (not just this
                // row's top) — matches swaync's default.notification-content
                // GTK box, which centers the image against the full,
                // possibly-multi-line text column next to it. Since this
                // RowLayout holds the entirety of the card's content (icon +
                // text), centering within the row achieves the same thing.
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
                spacing: 2

                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        id: summaryText
                        renderType: Text.NativeRendering
                        Layout.fillWidth: true
                        text: card.wrapper.summary
                        color: NotificationTheme.text
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: NotificationTheme.fontSize
                        elide: Text.ElideRight
                    }

                    Text {
                        id: timeText
                        renderType: Text.NativeRendering
                        // swaync only calls set_time() for control-center
                        // entries (controlCenter.vala) — a floating popup's
                        // time label is never populated, confirmed via a
                        // live screenshot showing no timestamp on the toast.
                        visible: !card.floating
                        text: card.wrapper.timeStr
                        color: NotificationTheme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: NotificationTheme.fontSize - 1
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    Layout.fillWidth: true
                    visible: card.wrapper.body !== ""
                    text: card.wrapper.body
                    color: NotificationTheme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: NotificationTheme.fontSize
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Individually rounded button chips, inset from the card's edges —
    // matches a live swaync screenshot (~/tmp/swaync-screenshot.png): each
    // action is its own bordered rectangle with visible fill at rest (not
    // just on hover), not a flush full-width bar split by a hairline.
    RowLayout {
        id: actionsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: mainColumn.bottom
        anchors.topMargin: card.actionsTopMargin
        anchors.leftMargin: card.actionsMargin
        anchors.rightMargin: card.actionsMargin
        visible: card.wrapper.otherActions.length > 0
        // Two adjacent buttons' own 4px `.notification-action` paddings plus
        // the row's own spacing, which is what the gap in the reference
        // screenshot measures out to (14px there, ~10 logical).
        spacing: 10

        Repeater {
            id: actionsRepeater
            model: card.wrapper.otherActions

            Rectangle {
                id: actionButton
                required property var modelData
                required property int index

                Layout.fillWidth: true
                // Equal preferred widths, so the row splits evenly and every
                // button ends up the same width regardless of how long its
                // label is — swaync's buttons are equal (312/311px in the
                // reference screenshot) even though "Mark as Read" is far
                // wider than "Delete". Without this, fillWidth would only
                // share the *leftover* space and leave each button sized
                // around its own label.
                Layout.preferredWidth: 1
                // A GTK button's height around a 16px label: the reference
                // screenshot's buttons are 56px tall at its ~1.36x scale.
                Layout.preferredHeight: 40
                // Not used for actual layout (the two Layout.preferred* above
                // win), only read by card.naturalWidth below as this button's
                // unsquished minimum — text padded 8px each side.
                implicitWidth: actionLabel.implicitWidth + 16
                // swaync's `.text-button { border-radius: 6px }` — deliberately
                // tighter than the card's own 10, which is what makes these
                // read as buttons inside the card rather than pills.
                radius: 6
                color: actionArea.containsMouse ? NotificationTheme.bgHover : NotificationTheme.bgButton
                border.width: 1
                border.color: NotificationTheme.borderNotification
                scale: actionPress.value

                PressSpring {
                    id: actionPress
                    pressed: actionArea.pressed
                }

                Text {
                    id: actionLabel
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: actionButton.modelData.text
                    color: NotificationTheme.text
                    font.family: Theme.fontFamily
                    // ExtraBold, not plain `bold` (700): swaync's labels render
                    // through GTK's own bold face, which is heavier than what
                    // Inter Variable gives at 700 — measured off the reference
                    // screenshot (~/tmp/swaync-screenshot.png), its labels'
                    // stroke width normalised to this monitor's scale is 5.6px
                    // against the 3.9px `font.bold` produced here. Selected by
                    // styleName rather than `font.weight: Font.ExtraBold`, which
                    // renders identically to plain bold — Qt won't pick a face
                    // past 700 off this variable font by weight alone, but it
                    // does honour the named instance fontconfig exposes.
                    font.styleName: "ExtraBold"
                    font.pixelSize: NotificationTheme.fontSize
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

    // Close button, anchored to the card's top-right corner rather than
    // inline in the header row (by request) — matches the usual toast
    // convention of a corner-pinned close affordance instead of one that
    // shares horizontal space with the summary/time text. Declared after
    // mainColumn/actionsRow so it sits on top and wins the hit-test over
    // the whole-card click-to-dismiss MouseArea above.
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

        Text {
            renderType: Text.NativeRendering
            anchors.centerIn: parent
            text: "✕"
            color: closeArea.containsMouse ? "black" : NotificationTheme.text
            font.pixelSize: 12
        }
    }

    // Selection/default border, as its own top-most overlay rather than
    // this Rectangle's own `border` — that paints underneath children, so a
    // border set there would sit below mainColumn/actionsRow's opaque
    // backgrounds instead of outlining the whole card. A plain Item has no
    // mouse handling of its own, so this doesn't steal clicks/hover from the
    // MouseAreas underneath despite painting on top of them.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? NotificationTheme.bgSelected : Qt.rgba(NotificationTheme.text.r, NotificationTheme.text.g, NotificationTheme.text.b, 0.1)
    }
}
