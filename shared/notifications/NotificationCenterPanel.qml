pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.shared
import qs.services
import qs.shared.animations
import qs.shared.notifications

// swaync's control-center panel: toggled from the bar's NotificationCenter
// indicator and pinned open regardless of cursor position. PopupCoordinator
// isn't used at all — it only tracks one hover-triggered owner — so
// visibility just gates off NotificationService.centerOpen.
//
// One shared window process-wide, instantiated from shell.qml, whose `screen`
// follows NotificationService.centerScreen so it opens on whichever output was
// clicked.
//
// Anchored to all four screen edges so the outer MouseArea can catch an
// outside click to close, rather than stacking a second layer-shell surface
// whose ordering isn't guaranteed. Fully unmapped while closed.
PanelWindow {
    id: panelWindow

    anchors {
        top: true
        right: true
        bottom: true
        left: true
    }

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Kept mapped through the close slide-out: unmapping the instant
    // centerOpen flips false would cut the animation off after a frame.
    //
    // `visible` deliberately does NOT reference centerOpen, only `open` and
    // `closing`, which the handler below writes together. Binding it to
    // centerOpen directly raced: that binding and the handler are independent
    // listeners on the same signal with no ordering between them, so when the
    // binding re-evaluated first it saw centerOpen already false and `closing`
    // still false, unmapping the window for a frame before the handler remapped
    // it. Routing both flags through one handler makes them change atomically,
    // so `visible` can never observe an inconsistent combination.
    property bool open: false
    property bool closing: false
    visible: open || closing

    Connections {
        target: NotificationService
        function onCenterOpenChanged() {
            // Order matters: each write fires its change signal synchronously,
            // with no batching between the two statements. Setting `closing`
            // before clearing `open` keeps `open || closing` true at every
            // intermediate point — the other order left a window where both
            // were false, unmapping and remapping inside one handler call.
            if (!NotificationService.centerOpen)
                panelWindow.closing = true;
            panelWindow.open = NotificationService.centerOpen;
            rightMarginSpring.retarget(NotificationService.centerOpen ? panel.restingRightMargin : panel.closedRightMargin);
        }
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    // Tied to centerOpen, not visible: the window stays mapped through the
    // slide-out, but focus should return to whatever's underneath the instant
    // the user closes it, not once the spring settles. This is a live
    // layer-shell surface update rather than a remap, so it takes effect while
    // the panel is still sliding away.
    WlrLayershell.keyboardFocus: NotificationService.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) {
        focusScope.forceActiveFocus();
        // Pre-select the first row on every open, rather than carrying a
        // stale index over or needing an extra keypress before Up/Down works.
        focusScope.selectedIndex = NotificationService.notificationGroups.length > 0 ? 0 : -1;
    }

    // Click-outside-to-close.
    MouseArea {
        anchors.fill: parent
        onClicked: NotificationService.closeCenter()
    }

    Item {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: NotificationService.closeCenter()

        // Keyboard selection into NotificationService.notificationGroups; -1
        // means nothing selected, only reachable once the list empties out
        // from under a selection. Up/Down move it, Return/Enter fire the row's
        // action, Delete/Backspace dismiss it.
        property int selectedIndex: -1

        function clampSelection() {
            const len = NotificationService.notificationGroups.length;
            if (focusScope.selectedIndex >= len)
                focusScope.selectedIndex = len - 1;
        }

        // Covers dismissal from any source, not just the key handler below:
        // the list can shrink out from under a keyboard selection whenever the
        // mouse is used at the same time.
        Connections {
            target: NotificationService
            function onNotificationsChanged() {
                focusScope.clampSelection();
            }
        }

        Keys.onUpPressed: {
            if (NotificationService.notificationGroups.length === 0)
                return;
            focusScope.selectedIndex = focusScope.selectedIndex <= 0 ? 0 : focusScope.selectedIndex - 1;
            notificationListView.positionViewAtIndex(focusScope.selectedIndex, ListView.Contain);
        }

        Keys.onDownPressed: {
            const len = NotificationService.notificationGroups.length;
            if (len === 0)
                return;
            focusScope.selectedIndex = focusScope.selectedIndex < 0 ? 0 : Math.min(focusScope.selectedIndex + 1, len - 1);
            notificationListView.positionViewAtIndex(focusScope.selectedIndex, ListView.Contain);
        }

        Keys.onReturnPressed: focusScope.activateSelected()
        Keys.onEnterPressed: focusScope.activateSelected()

        // Return on a single-notification row fires its default action, like
        // clicking the body; on a group it toggles expand/collapse.
        function activateSelected() {
            const groups = NotificationService.notificationGroups;
            if (focusScope.selectedIndex < 0 || focusScope.selectedIndex >= groups.length)
                return;
            const group = groups[focusScope.selectedIndex];
            if (group.items.length === 1) {
                const wrapper = group.items[0];
                if (wrapper.defaultAction)
                    wrapper.defaultAction.invoke();
            } else {
                NotificationService.toggleGroupExpanded(group.key);
            }
        }

        Keys.onDeletePressed: focusScope.dismissSelected()
        // There's no Keys.onBackspacePressed signal, and Qt.Key_Back is the
        // browser-style back key, not Backspace — hence the generic handler.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Backspace) {
                focusScope.dismissSelected();
                event.accepted = true;
            }
        }

        function dismissSelected() {
            const groups = NotificationService.notificationGroups;
            if (focusScope.selectedIndex < 0 || focusScope.selectedIndex >= groups.length)
                return;
            NotificationService.dismissGroup(groups[focusScope.selectedIndex]);
        }

        // The panel itself: left corners rounded only, flush against the
        // right screen edge, the same per-corner-radius technique
        // ModuleGroup.qml uses for the bar's pills. It slides in and out by
        // animating rightMargin between resting and fully off-screen, rather
        // than toggling visibility.
        //
        // The resting -2 is a deliberate 2px overscan, not a bug: at
        // Hyprland's fractional scale a rightMargin of 0 left the screen's
        // last physical column transparent, since the window's own background
        // is transparent and only this child Rectangle paints. (Bar.qml
        // doesn't hit this — its background is the window's own `color`.) The
        // extra 2px are square and land past the true screen edge, so the
        // compositor clips them.
        Rectangle {
            id: panel
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: NotificationTheme.controlCenterMarginV
            anchors.rightMargin: rightMarginSpring.value
            width: NotificationTheme.controlCenterWidth

            readonly property real restingRightMargin: -2
            readonly property real closedRightMargin: -panel.width - 2

            // Driven imperatively rather than declaratively: retarget() is
            // called from the Connections handler above on every centerOpen
            // change.
            FrameSpring {
                id: rightMarginSpring
                // Softer than Theme's defaults, overridden here rather than
                // globally since those are shared with the modules' width
                // springs. Same near-critical damping ratio (~1.05, so still
                // no wobble), lower natural frequency: ~185ms settle instead
                // of ~137ms, a deliberately slower slide for this panel.
                stiffness: 160
                damping: 18
                Component.onCompleted: snapTo(panel.closedRightMargin)
                onRunningChanged: if (!running && !NotificationService.centerOpen)
                    panelWindow.closing = false
            }

            color: NotificationTheme.bgGlobal
            border.width: 1
            border.color: NotificationTheme.borderSubtle
            topLeftRadius: NotificationTheme.controlCenterRadius
            bottomLeftRadius: NotificationTheme.controlCenterRadius
            topRightRadius: 0
            bottomRightRadius: 0

            // Consumes clicks inside the panel so they don't fall through to
            // the outer close-catcher.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                // See NotificationTheme's panelPadding/panelSpacing.
                anchors.margins: NotificationTheme.panelPadding
                spacing: NotificationTheme.panelSpacing

                // ---- header ----
                // No Clear All button, matching this swaync config. Clearing
                // is still reachable via the `notifications clear` IPC call
                // (see shell.qml), just not from the UI.
                StyledText {
                    text: "Notifications"
                    color: NotificationTheme.text
                    font.pixelSize: NotificationTheme.fontSizeTitle
                }

                // ---- DND ----
                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: "Do Not Disturb"
                        color: NotificationTheme.text
                        font.pixelSize: NotificationTheme.fontSize
                    }

                    Rectangle {
                        Layout.preferredWidth: NotificationTheme.switchWidth
                        Layout.preferredHeight: NotificationTheme.switchHeight
                        radius: height / 2
                        color: NotificationService.dnd ? NotificationTheme.bgSelected : NotificationTheme.bg
                        border.width: NotificationService.dnd ? 0 : 1
                        border.color: NotificationTheme.borderColor

                        Rectangle {
                            width: parent.height - NotificationTheme.switchPadding * 2
                            height: parent.height - NotificationTheme.switchPadding * 2
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: NotificationService.dnd ? parent.width - width - NotificationTheme.switchPadding : NotificationTheme.switchPadding
                            color: NotificationTheme.bgHover

                            Behavior on x {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.dnd = !NotificationService.dnd
                        }
                    }
                }

                // ---- notification list ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Matches swaync's control-center-list-placeholder: an
                    // icon above the label, the whole group at half opacity
                    // (style.css's `.control-center-list-placeholder {
                    // opacity: 0.5 }`) rather than just dimming the text.
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: NotificationService.notifications.length === 0
                        opacity: 0.5
                        spacing: 8

                        IconImage {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            implicitSize: 64
                            source: Quickshell.iconPath("notification-disabled-symbolic", "dialog-information-symbolic")
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "No Notifications"
                            color: NotificationTheme.text
                            font.pixelSize: NotificationTheme.fontSize
                        }
                    }

                    ListView {
                        id: notificationListView
                        anchors.fill: parent
                        clip: true
                        // A card sits further in than the title/DND labels
                        // above it — see NotificationTheme.listPadding, which
                        // stacks on the ColumnLayout's own panelPadding.
                        // Vertically each row carries listCardMargin above and
                        // below, so stacked cards sit twice that apart while
                        // the first and last still clear the list's bounds.
                        spacing: NotificationTheme.listCardMargin * 2
                        leftMargin: NotificationTheme.listPadding
                        rightMargin: NotificationTheme.listPadding
                        topMargin: NotificationTheme.listCardMargin
                        bottomMargin: NotificationTheme.listCardMargin
                        model: NotificationService.notificationGroups

                        delegate: NotificationGroupCard {
                            id: listCard
                            required property var modelData
                            required property int index
                            // Not `ListView.view.width` alone: that's the
                            // full viewport, ignoring the view's own left and
                            // right margins, so cards overflowed them and got
                            // clipped — a visible seam on the selected card's
                            // right edge.
                            width: ListView.view.width - notificationListView.leftMargin - notificationListView.rightMargin
                            group: listCard.modelData
                            selected: focusScope.selectedIndex === listCard.index
                        }
                    }
                }

                // ---- now playing (mpris) ----
                // Generic MPRIS widget like swaync's: whatever is active over
                // MPRIS, not tied to a specific player. MprisService owns which
                // player shows and the paging between them; this is its view.
                // The </> arrows and dots appear once a second player does.
                ColumnLayout {
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

                            // On a player switch the card stays put and only
                            // its content slides. MprisService.slideDirection
                            // is set right before the index write rather than
                            // inferred from the delta, whose sign is ambiguous
                            // when the selection wraps.
                            readonly property int watchedIndex: MprisService.index
                            onWatchedIndexChanged: {
                                mprisSlideSpring.value = MprisService.slideDirection * mprisClip.width;
                                mprisSlideSpring.retarget(0);
                            }

                            // Same player, new track: a small scale bounce
                            // instead of a slide. Suppressed when the track
                            // changed as a side effect of switching players,
                            // so the two effects never stack.
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
                                // The default epsilon is tuned for
                                // pixel-scale springs, too coarse for this
                                // 0..1 bump — see PressSpring.qml.
                                epsilon: 0.002
                            }

                            // Drives both content layers' x. A full
                            // card-width of travel, so it has to be slow
                            // enough to read as motion across that distance;
                            // settle time is independent of distance, so the
                            // same constants work at any card width. Damping
                            // ratio ~0.76, a little lighter than critical, so
                            // it gives slightly at the end rather than gliding
                            // to a dead stop.
                            FrameSpring {
                                id: mprisSlideSpring
                                value: 0
                                target: 0
                                stiffness: 60
                                damping: 13
                                mass: 0.8
                            }

                            // Clips the sliding layers to the card's content
                            // area, so a page swaps inside a fixed frame
                            // rather than spilling past its rounded edges.
                            Item {
                                id: mprisClip
                                anchors.fill: parent
                                anchors.margins: 12
                                clip: true

                                // Outgoing: the player just shown, sliding
                                // out the opposite side from the incoming
                                // one. On screen only for the slide, and never
                                // interactive.
                                MprisNowPlayingContent {
                                    width: mprisClip.width
                                    height: mprisClip.height
                                    visible: mprisSlideSpring.running && MprisService.previousPlayer !== null
                                    player: MprisService.previousPlayer
                                    interactive: false
                                    x: mprisSlideSpring.value - MprisService.slideDirection * mprisClip.width
                                }

                                // Incoming: the current player, always the
                                // interactive layer. Starts a full card-width
                                // out and slides to 0.
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
            }
        }

        // swaync's `.control-center` box-shadow, the same
        // MultiEffect-as-source pattern as NotificationCard.qml's.
        MultiEffect {
            anchors.fill: panel
            source: panel
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.4
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 1
            shadowBlur: 0.4
        }
    }
}
