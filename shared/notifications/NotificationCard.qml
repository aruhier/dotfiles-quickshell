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

    // No trailing `+ padding` when actionsRow is visible — its buttons sit
    // flush with the card's bottom edge (see the border-overlay comment
    // below), so adding bottom padding here would leave a gap below them
    // where the card's own rounded background shows through.
    implicitHeight: padding * 2 + mainColumn.implicitHeight + (actionsRow.visible ? actionsRow.height : 0)

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
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.preferredWidth: card.iconSize
                Layout.preferredHeight: card.iconSize
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
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
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

    RowLayout {
        id: actionsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: mainColumn.bottom
        anchors.topMargin: card.padding
        visible: card.wrapper.otherActions.length > 0
        spacing: 1

        Repeater {
            model: card.wrapper.otherActions

            Rectangle {
                id: actionButton
                required property var modelData
                required property int index

                // 28 (the visual button height, centered text) plus
                // card.padding baked in as the button's own bottom margin —
                // it needs to reach the card's true bottom edge (see the
                // border-overlay comment below), so that trailing space has
                // to belong to the button's fill/hover color rather than be
                // left as a gap after actionsRow where the card's own
                // background would show through.
                Layout.fillWidth: true
                Layout.preferredHeight: 28 + card.padding
                color: actionArea.containsMouse ? NotificationTheme.bgHover : (card.floating ? "transparent" : NotificationTheme.bg)
                bottomLeftRadius: index === 0 ? card.radius : 0
                bottomRightRadius: index === card.wrapper.otherActions.length - 1 ? card.radius : 0
                scale: actionPress.value

                PressSpring {
                    id: actionPress
                    pressed: actionArea.pressed
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: actionButton.modelData.text
                    color: NotificationTheme.text
                    font.family: Theme.fontFamily
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
    // this Rectangle's own `border` — that paints underneath children, and
    // actionsRow's buttons sit flush with the card's outer edges (no
    // margins) with an opaque background, so they'd fully cover the border
    // along the bottom/side strip where they sit — a visible break in the
    // outline, worst on the 2px selected border. A plain Item has no mouse
    // handling of its own, so this doesn't steal clicks/hover from the
    // MouseAreas underneath despite painting on top of them.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? NotificationTheme.bgSelected : Qt.rgba(NotificationTheme.text.r, NotificationTheme.text.g, NotificationTheme.text.b, 0.1)
    }
}
