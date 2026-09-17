pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.shared
import qs.shared.animations
import qs.shared.notifications
import qs.themes

// The control centre's now-playing widget: any MPRIS player, not a specific
// one. MprisService owns selection and paging; this is its view, and
// MprisNowPlayingContent.qml is one page of it.
//
// Two gestures, deliberately exclusive: a player switch slides the pages,
// a new track on the same player pops the plate. See notes/notifications.md.
ColumnLayout {
    id: root

    Layout.fillWidth: true
    visible: MprisService.activePlayer !== null
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        PressableIcon {
            visible: MprisService.players.length > 1
            text: "󰅁"
            color: NotificationTheme.text
            font.pixelSize: NotificationTheme.mprisControlIconSize - 4
            onActivated: MprisService.prev()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: incomingContent.implicitHeight + 24
            radius: 14
            color: NotificationTheme.bgHover
            scale: mprisPopSpring.value

            // On a player switch only the content slides.
            // slideDirection comes from MprisService because
            // the index delta's sign is ambiguous on wrap.
            readonly property int watchedIndex: MprisService.index
            onWatchedIndexChanged: {
                mprisSlideSpring.value = MprisService.slideDirection * mprisClip.width;
                mprisSlideSpring.retarget(0);
            }

            // Same player, new track: a scale bounce instead
            // of a slide. Suppressed on a player switch so the
            // two effects never stack.
            readonly property string trackKey: MprisService.activePlayer ? MprisService.activePlayer.trackTitle + "|" + MprisService.activePlayer.trackArtist : ""
            onTrackKeyChanged: {
                if (MprisService.suppressPop)
                    return;
                mprisPopSpring.value = 0.94;
                mprisPopSpring.retarget(1);
            }

            FrameSpring {
                id: mprisPopSpring
                value: 1
                target: 1
                // Default epsilon is pixel-scale, too coarse
                // for a 0..1 bump — see PressSpring.qml.
                epsilon: 0.002
            }

            // Drives both content layers' x over a full
            // card-width of travel, slow enough to read as
            // motion. Damping ratio ~0.76, slightly under
            // critical, so it gives at the end.
            FrameSpring {
                id: mprisSlideSpring
                value: 0
                target: 0
                stiffness: 60
                damping: 13
                mass: 0.8
            }

            // Clips the sliding layers so a page swaps inside
            // a fixed frame, not past the rounded edges.
            Item {
                id: mprisClip
                anchors.fill: parent
                anchors.margins: 12
                clip: true

                // Outgoing: on screen only for the slide, and
                // never interactive.
                MprisNowPlayingContent {
                    width: mprisClip.width
                    height: mprisClip.height
                    visible: mprisSlideSpring.running && MprisService.previousPlayer !== null
                    player: MprisService.previousPlayer
                    interactive: false
                    x: mprisSlideSpring.value - MprisService.slideDirection * mprisClip.width
                }

                // Incoming: the current player, always the
                // interactive layer.
                MprisNowPlayingContent {
                    id: incomingContent
                    width: mprisClip.width
                    height: mprisClip.height
                    player: MprisService.activePlayer
                    x: mprisSlideSpring.value
                }
            }
        }

        PressableIcon {
            visible: MprisService.players.length > 1
            text: "󰅂"
            color: NotificationTheme.text
            font.pixelSize: NotificationTheme.mprisControlIconSize - 4
            onActivated: MprisService.next()
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        visible: MprisService.players.length > 1
        spacing: 6

        Repeater {
            model: MprisService.players.length

            Rectangle {
                required property int index
                width: 6
                height: 6
                radius: 3
                color: index === MprisService.index ? NotificationTheme.text : NotificationTheme.textDisabled
            }
        }
    }
}
