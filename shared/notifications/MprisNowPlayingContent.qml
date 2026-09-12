pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.shared
import qs.shared.notifications

// The art/title/artist/transport row of the now-playing widget. Its own type
// so the widget can render two at once, one sliding out as the other slides
// in. `player` may be null, so every binding guards for it.
RowLayout {
    id: root

    required property var player
    // False for the outgoing layer mid-slide, so a copy on its way out doesn't
    // answer clicks meant for the incoming one.
    property bool interactive: true

    spacing: 14

    ClippingRectangle {
        Layout.preferredWidth: NotificationTheme.mprisImageSize
        Layout.preferredHeight: NotificationTheme.mprisImageSize
        radius: NotificationTheme.mprisImageRadius
        color: NotificationTheme.bg

        Image {
            anchors.fill: parent
            visible: root.player && root.player.trackArtUrl !== ""
            source: root.player ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            Layout.fillWidth: true
            text: root.player ? root.player.trackTitle : ""
            color: NotificationTheme.text
            font.pixelSize: NotificationTheme.mprisTitleFontSize
            bold: true
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            text: root.player ? root.player.trackArtist : ""
            color: NotificationTheme.text
            font.pixelSize: NotificationTheme.mprisArtistFontSize
            elide: Text.ElideRight
        }

        RowLayout {
            spacing: 12
            Layout.alignment: Qt.AlignHCenter

            PressableIcon {
                text: "󰒝"
                color: root.player && root.player.shuffleSupported ? (root.player.shuffle ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize - 4
                interactive: root.interactive && root.player && root.player.shuffleSupported
                onActivated: root.player.shuffle = !root.player.shuffle
            }

            PressableIcon {
                text: "󰒮"
                color: root.player && root.player.canGoPrevious ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize
                interactive: root.interactive && root.player && root.player.canGoPrevious
                onActivated: root.player.previous()
            }

            PressableIcon {
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                color: root.player && root.player.canTogglePlaying ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize
                interactive: root.interactive && root.player && root.player.canTogglePlaying
                onActivated: root.player.togglePlaying()
            }

            PressableIcon {
                text: "󰒭"
                color: root.player && root.player.canGoNext ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize
                interactive: root.interactive && root.player && root.player.canGoNext
                onActivated: root.player.next()
            }

            PressableIcon {
                text: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                color: root.player && root.player.loopSupported ? (root.player.loopState !== MprisLoopState.None ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize - 4
                interactive: root.interactive && root.player && root.player.loopSupported
                onActivated: {
                    if (root.player.loopState === MprisLoopState.None)
                        root.player.loopState = MprisLoopState.Playlist;
                    else if (root.player.loopState === MprisLoopState.Playlist)
                        root.player.loopState = MprisLoopState.Track;
                    else
                        root.player.loopState = MprisLoopState.None;
                }
            }
        }
    }
}
