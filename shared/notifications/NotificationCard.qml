import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../../services"

// One notification's visual — reused by both the popup stack
// (NotificationPopupWindow.qml, floating: true) and the control-center list
// (NotificationCenterPanel.qml, floating: false). Caller supplies `width`;
// height follows content via implicitHeight.
Rectangle {
    id: card

    required property var wrapper
    property bool floating: false

    property int padding: 8
    property int iconSize: 40

    implicitHeight: padding * 2 + mainColumn.implicitHeight + (actionsRow.visible ? actionsRow.height + padding : 0)

    radius: NotificationTheme.cardRadius
    color: floating ? NotificationTheme.bgFloating : NotificationTheme.bg
    border.width: 1
    border.color: Qt.rgba(NotificationTheme.text.r, NotificationTheme.text.g, NotificationTheme.text.b, 0.1)

    // Body click invokes the default action, if the sender declared one —
    // matches swaync's notification.vala click_default_action(). Covers
    // just mainColumn's area, not the actions row below it.
    MouseArea {
        anchors.fill: mainColumn
        enabled: card.wrapper.defaultAction !== null
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
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: card.wrapper.timeStr
                        color: NotificationTheme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }

                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        radius: 9
                        color: "black"

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
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
                    font.pixelSize: Theme.fontSize
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

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: actionButton.modelData.text
                    color: NotificationTheme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: actionButton.modelData.invoke()
                }
            }
        }
    }
}
