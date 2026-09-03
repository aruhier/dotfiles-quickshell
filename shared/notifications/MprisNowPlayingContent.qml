import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import ".."
import "../animations"

// One MPRIS "now playing" card's content — the art/title/artist/transport
// row from NotificationCenterPanel.qml's now-playing widget, factored out so
// that widget can render two independent instances side by side (an
// outgoing player's content sliding out, an incoming player's content
// sliding in during a player switch) without id collisions between their
// two separate sets of press-spring buttons. `player` may be null (no
// previous player yet, or no active player at all) — every binding below
// guards for that, same as the original inline version's own
// `panelWindow.activePlayer &&` guards.
RowLayout {
    id: root

    required property var player
    // False for the outgoing/peeking layer during a player-switch slide —
    // same idea as NotificationCard.qml's own `interactive` doc comment: a
    // copy that's on its way out shouldn't answer clicks meant for the
    // incoming layer sliding in alongside it.
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

        Text {
            renderType: Text.NativeRendering
            Layout.fillWidth: true
            text: root.player ? root.player.trackTitle : ""
            color: NotificationTheme.text
            font.family: Theme.fontFamily
            font.pixelSize: NotificationTheme.mprisTitleFontSize
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            renderType: Text.NativeRendering
            Layout.fillWidth: true
            text: root.player ? root.player.trackArtist : ""
            color: NotificationTheme.text
            font.family: Theme.fontFamily
            font.pixelSize: NotificationTheme.mprisArtistFontSize
            elide: Text.ElideRight
        }

        RowLayout {
            spacing: 12

            Text {
                renderType: Text.NativeRendering
                text: "󰒝"
                color: root.player && root.player.shuffleSupported ? (root.player.shuffle ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                font.family: Theme.fontFamily
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

            Text {
                renderType: Text.NativeRendering
                text: "󰒮"
                color: root.player && root.player.canGoPrevious ? NotificationTheme.text : NotificationTheme.textDisabled
                font.family: Theme.fontFamily
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

            Text {
                renderType: Text.NativeRendering
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                color: root.player && root.player.canTogglePlaying ? NotificationTheme.text : NotificationTheme.textDisabled
                font.family: Theme.fontFamily
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

            Text {
                renderType: Text.NativeRendering
                text: "󰒭"
                color: root.player && root.player.canGoNext ? NotificationTheme.text : NotificationTheme.textDisabled
                font.family: Theme.fontFamily
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

            Text {
                renderType: Text.NativeRendering
                text: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                color: root.player && root.player.loopSupported ? (root.player.loopState !== MprisLoopState.None ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                font.family: Theme.fontFamily
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
                    // Inlined from the panel's old cycleLoopState() —
                    // that operated on the single global activePlayer, but
                    // this component renders two independent players (the
                    // outgoing and incoming layers) so the logic now has to
                    // work off root.player instead.
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
