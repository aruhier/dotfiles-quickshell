pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.shared
import qs.shared.animations
import qs.shared.notifications

// One MPRIS now-playing card's content: the art/title/artist/transport row of
// the control center's now-playing widget. Its own type so that widget can
// render two independent instances at once — an outgoing player's content
// sliding out beside an incoming one sliding in — without id collisions
// between their press-spring buttons. `player` may be null (no previous
// player, or none at all), so every binding guards for it.
RowLayout {
    id: root

    required property var player
    // False for the outgoing layer during a player-switch slide: a copy on
    // its way out shouldn't answer clicks meant for the incoming one.
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
            font.bold: true
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

            StyledText {
                text: "󰒝"
                color: root.player && root.player.shuffleSupported ? (root.player.shuffle ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize - 4
                scale: shufflePress.value

                PressSpring {
                    id: shufflePress
                    pressed: shuffleArea.pressed
                }

                MouseArea {
                    id: shuffleArea
                    anchors.fill: parent
                    enabled: root.interactive && root.player && root.player.shuffleSupported
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
            }

            StyledText {
                text: "󰒮"
                color: root.player && root.player.canGoPrevious ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize
                scale: prevTrackPress.value

                PressSpring {
                    id: prevTrackPress
                    pressed: prevTrackArea.pressed
                }

                MouseArea {
                    id: prevTrackArea
                    anchors.fill: parent
                    enabled: root.interactive && root.player && root.player.canGoPrevious
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.previous()
                }
            }

            StyledText {
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                color: root.player && root.player.canTogglePlaying ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize
                scale: playPausePress.value

                PressSpring {
                    id: playPausePress
                    pressed: playPauseArea.pressed
                }

                MouseArea {
                    id: playPauseArea
                    anchors.fill: parent
                    enabled: root.interactive && root.player && root.player.canTogglePlaying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.togglePlaying()
                }
            }

            StyledText {
                text: "󰒭"
                color: root.player && root.player.canGoNext ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize
                scale: nextTrackPress.value

                PressSpring {
                    id: nextTrackPress
                    pressed: nextTrackArea.pressed
                }

                MouseArea {
                    id: nextTrackArea
                    anchors.fill: parent
                    enabled: root.interactive && root.player && root.player.canGoNext
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.next()
                }
            }

            StyledText {
                text: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                color: root.player && root.player.loopSupported ? (root.player.loopState !== MprisLoopState.None ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.mprisControlIconSize - 4
                scale: loopPress.value

                PressSpring {
                    id: loopPress
                    pressed: loopArea.pressed
                }

                MouseArea {
                    id: loopArea
                    anchors.fill: parent
                    enabled: root.interactive && root.player && root.player.loopSupported
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
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
}
