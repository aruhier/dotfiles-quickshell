import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../../services"
import "../animations"

// One notification's visual — reused by both the popup stack
// (NotificationPopupWindow.qml, floating: true) and the control-center list
// (NotificationCenterPanel.qml, floating: false). Caller supplies `width`;
// height follows content via implicitHeight.
Rectangle {
    id: card

    required property var wrapper
    property bool floating: false
    // Keyboard selection in NotificationCenterPanel's list — floating
    // popups never set this, they have no keyboard focus to select with.
    property bool selected: false

    property int padding: 8
    property int iconSize: 40

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

    implicitHeight: padding * 2 + mainColumn.implicitHeight + (actionsRow.visible ? actionsRow.height + padding : 0)

    radius: NotificationTheme.cardRadius
    color: floating ? NotificationTheme.bgFloating : NotificationTheme.bg

    // Body click invokes the default action, if the sender declared one —
    // matches swaync's notification.vala click_default_action(). Covers
    // just mainColumn's area, not the actions row below it.
    MouseArea {
        anchors.fill: mainColumn
        enabled: card.interactive && card.wrapper.defaultAction !== null
        cursorShape: card.wrapper.defaultAction !== null ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: card.wrapper.defaultAction.invoke()
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
                Layout.alignment: Qt.AlignTop

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

                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        radius: 9
                        color: "black"
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
                            radius: 9
                            visible: closeArea.containsMouse
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

                Layout.fillWidth: true
                Layout.preferredHeight: 28
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
