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

// The notification control center: click-toggled and pinned open, so it gates
// off NotificationService.centerOpen rather than PopupCoordinator (which only
// tracks one hover-triggered owner). One shared window process-wide, its
// `screen` following centerScreen so it opens on the clicked output.
// Anchored to all four edges so the outer MouseArea catches outside clicks —
// a second layer-shell surface would have no guaranteed stacking order.
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

    // Kept mapped through the close slide-out. `visible` must not reference
    // centerOpen: as an independent listener it can see centerOpen false while
    // `closing` is still unset, unmapping for a frame. One handler writing both
    // flags makes them change atomically.
    property bool open: false
    property bool closing: false
    visible: open || closing

    Connections {
        target: NotificationService
        function onCenterOpenChanged() {
            // Writes fire their signals synchronously and unbatched, so
            // `closing` must be set before `open` clears to keep `open ||
            // closing` true at every intermediate point.
            if (!NotificationService.centerOpen)
                panelWindow.closing = true;
            panelWindow.open = NotificationService.centerOpen;
            if (NotificationService.centerOpen) {
                // Cleared here, not only when the exit finishes: reopening
                // mid-close leaves `closing` set otherwise, and the spring
                // reads it to know which stage it is in. Ordered after the
                // write above so `open || closing` never dips false.
                panelWindow.closing = false;
                panel.bumped = false;
                rightMarginSpring.retarget(panel.bumpAim);
            } else {
                panel.wound = false;
                rightMarginSpring.retarget(panel.windUpAim);
            }
        }
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    // Tied to centerOpen, not visible: focus returns underneath the instant
    // the user closes, not once the slide-out spring settles.
    WlrLayershell.keyboardFocus: NotificationService.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) {
        focusScope.forceActiveFocus();
        // Pre-select the first row, so Up/Down works without a priming press.
        focusScope.selectedKey = NotificationService.notificationGroups.length > 0 ? NotificationService.notificationGroups[0].key : "";
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

        // Keyed by group key, not row index: the list re-sorts under the
        // selection when a notification arrives, so an index would silently
        // come to mean a different group. "" = nothing selected (empty list).
        property string selectedKey: ""

        readonly property int selectedIndex: {
            const groups = NotificationService.notificationGroups;
            for (let i = 0; i < groups.length; i++) {
                if (groups[i].key === focusScope.selectedKey)
                    return i;
            }
            return -1;
        }

        // So dismissing the selected group lands the selection on whatever
        // slid up into that row rather than dropping it.
        property int lastSelectedIndex: 0
        onSelectedIndexChanged: if (focusScope.selectedIndex >= 0)
            focusScope.lastSelectedIndex = focusScope.selectedIndex

        // Covers dismissal from any source: the mouse can shrink the list out
        // from under a keyboard selection.
        Connections {
            target: NotificationService
            function onNotificationsChanged() {
                if (focusScope.selectedIndex >= 0)
                    return;
                const groups = NotificationService.notificationGroups;
                focusScope.selectedKey = groups.length === 0 ? "" : groups[Math.min(focusScope.lastSelectedIndex, groups.length - 1)].key;
            }
        }

        function moveSelection(delta) {
            const groups = NotificationService.notificationGroups;
            if (groups.length === 0)
                return;
            // From no selection, either direction lands on the first row.
            const next = focusScope.selectedIndex < 0 ? 0 : Math.max(0, Math.min(focusScope.selectedIndex + delta, groups.length - 1));
            focusScope.selectedKey = groups[next].key;
            notificationListView.positionViewAtIndex(next, ListView.Contain);
        }

        Keys.onUpPressed: focusScope.moveSelection(-1)
        Keys.onDownPressed: focusScope.moveSelection(1)

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
            // Through the row, so it plays its exit gesture; a row scrolled far
            // enough out of the view has no delegate to ask.
            const row = notificationListView.itemAtIndex(focusScope.selectedIndex) as NotificationGroupCard;
            if (row)
                row.dismiss();
            else
                NotificationService.dismissGroup(groups[focusScope.selectedIndex]);
        }

        // Slides in and out by animating rightMargin, rather than toggling
        // visibility. It is drawn `edgeOverscan` wider than it reads and rests
        // that far past the screen edge, so the opening bump pulls that slack
        // in instead of opening a gap to the edge — and so the last physical
        // column, which a flush margin leaves transparent at fractional scale
        // since only this Rectangle paints, is covered. That side is square,
        // and what sits past the edge is compositor-clipped.
        //
        // Every *resting* offset that places this Rectangle goes through
        // `Screens.snap()`, width included — right-anchored, so margin *and*
        // width decide where the left edge lands. Mid-gesture it is off the
        // grid on purpose; see the margin binding below. That is for this
        // Rectangle's own 1px border: off the device pixel grid it draws as
        // two half-lit columns instead of one solid one. The panel's *text*
        // does not depend on it (Qt rounds glyph positions); what text needed
        // was getting out of the shadow's layer, below.
        Rectangle {
            id: panel
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Screens.snap(NotificationTheme.controlCenterMarginV, panelWindow.screen)
            // Deliberately *not* snapped per frame, though every resting
            // offset here is: the slow tail of a gesture then advances a whole
            // device pixel at a time, which reads as stepping. Measured, at
            // 1.25 scale: 0.8px every ~10ms on a 240Hz output.
            //
            // The *landing* is the exception. Glyph origins are rounded to
            // whole device pixels while this plate is resampled continuously,
            // so over the last couple of device pixels the text takes its final
            // step alone, while the panel is creeping too slowly to read as
            // moving — which looks like the text shifting inside its card.
            // Snapped over that window, plate and text step together instead.
            // See notes/text.md.
            readonly property real devicePixel: 1 / Screens.scaleFor(panelWindow.screen)
            readonly property bool landing: !panelWindow.closing && panel.bumped && Math.abs(rightMarginSpring.value - panel.restingRightMargin) <= 2 * panel.devicePixel
            anchors.rightMargin: panel.landing ? Screens.snap(rightMarginSpring.value, panelWindow.screen) : rightMarginSpring.value
            // Snapped separately and added, rather than snapping the sum: the
            // left edge lands at `width - edgeOverscan`, so both have to be on
            // the device pixel grid for it to be.
            readonly property real visibleWidth: Screens.snap(NotificationTheme.controlCenterWidth, panelWindow.screen)
            readonly property real edgeOverscan: Screens.snap(NotificationTheme.controlCenterOverscan, panelWindow.screen)
            width: panel.visibleWidth + panel.edgeOverscan

            readonly property real restingRightMargin: -panel.edgeOverscan
            // Off-screen, so it only has to clear the edge, not land on it.
            readonly property real closedRightMargin: -panel.width - 2

            // A bigger margin is further left, so both bumps — the arrival's,
            // past the edge, and the exit's wind-up, onto the screen — are
            // *above* the resting margin, and the drop is far below it.
            //
            // Each stage is aimed past the line that ends it and caught there
            // by a latch: a spring decelerates into its target, so aiming past
            // the bump arrives at it slowly and releases from near rest, where
            // a spring aimed *at* it would still be at full speed. That is the
            // whole difference between this and one under damped spring, which
            // crosses its resting line fast and rings back. See notes/panels.md.
            readonly property real bumpLine: panel.restingRightMargin + NotificationTheme.controlCenterBump
            readonly property real bumpAim: panel.restingRightMargin + NotificationTheme.controlCenterBump * 1.2
            readonly property real windUpLine: panel.restingRightMargin + NotificationTheme.controlCenterDismissBump
            readonly property real windUpAim: panel.restingRightMargin + NotificationTheme.controlCenterDismissBump * 1.2
            // Aimed past the edge rather than at it: the last sliver of a
            // panel creeping away reads as an ease-out on an exit.
            readonly property real dropAim: panel.closedRightMargin - (panel.restingRightMargin - panel.closedRightMargin) * 0.5

            // Latched rather than compared, because the spring crosses each
            // line and comes back over it.
            property bool bumped: false
            property bool wound: false

            // The panel's inner inset, and where the list's left edge sits in
            // the window once the panel is at rest. The card inset is solved
            // against this rather than snapped on its own: what a text subtree
            // needs is a whole logical landing place, and where that is
            // depends on where the panel has landed on this output. Off the
            // *resting* geometry and never the live x — re-solving it
            // mid-slide would walk the list sideways inside the panel.
            readonly property real contentInset: Screens.snap(NotificationTheme.panelPadding, panelWindow.screen)
            readonly property real listEdge: panelWindow.width - panel.visibleWidth + panel.contentInset

            // Retargeted imperatively from the Connections handler above.
            //
            // Four stages on one spring, every one of them critically damped,
            // switched on the two latches: sweep in and ease into the bump,
            // settle back out of it, wind up onto the screen, drop off the
            // edge. One spring rather than two so a gesture interrupted
            // mid-flight — closing while still arriving — picks up the panel
            // where it actually is instead of jumping.
            FrameSpring {
                id: rightMarginSpring
                // The sweep is soft enough to read at 500px of travel, the
                // settle stiffer since it only has the bump to undo, and the
                // exit's pair are the toasts' own — the wind-up stiff so it
                // covers its distance *and* arrives, the drop soft enough not
                // to snatch. Scale a pair to change the pace, never the
                // stiffness alone; the knob is in notes/osd.md. The opening
                // pair have been through it once, at 1.15.
                stiffness: panelWindow.closing ? (panel.wound ? 72 : 455) : (panel.bumped ? 345 : 227)
                damping: panelWindow.closing ? (panel.wound ? 13.4 : 32.9) : (panel.bumped ? 28.8 : 23.3)
                onValueChanged: {
                    if (panelWindow.closing) {
                        if (!panel.wound) {
                            if (value >= panel.windUpLine) {
                                panel.wound = true;
                                retarget(panel.dropAim);
                            }
                        } else if (value <= panel.closedRightMargin) {
                            // Parked the moment the panel is clear; settling is
                            // what unmaps the window, below.
                            snapTo(panel.closedRightMargin);
                        }
                    } else if (!panel.bumped) {
                        if (value >= panel.bumpLine) {
                            panel.bumped = true;
                            retarget(panel.restingRightMargin);
                        }
                    } else if (Math.abs(value - panel.restingRightMargin) <= 0.5 * panel.devicePixel) {
                        // Parked once the rendered position can no longer
                        // change. The stop condition in FrameSpring compares a
                        // velocity in px/s against a pixel epsilon, so a
                        // critically damped settle goes on integrating for
                        // ~130ms after it has visibly arrived — frames that can
                        // only produce the sub-pixel drift above.
                        snapTo(panel.restingRightMargin);
                    }
                }
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
        }

        // Drop shadow, the same MultiEffect-as-source pattern as
        // NotificationCard.qml's: `panel` is the source and so paints only
        // through here, never directly.
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

        // Everything the panel *shows* lives here, a sibling of the shadow's
        // source rather than a child of it, so `panel` stays an empty
        // background plate. A source item is rendered into a layer texture and
        // that texture is drawn with linear filtering, so whenever the item
        // lands on a fraction of a device pixel — routine at fractional scale
        // — the whole subtree inside it is resampled. Qt rounds glyph
        // positions for ordinary items, so unlayered text is immune at any
        // offset; text *inside* a layer is not, and this panel used to put its
        // entire contents in one. Measured: AGENTS.md.
        Item {
            // Fills what reads, not the overscan: the slack past the screen
            // edge is background, so the layout's padding still measures from
            // the visible edge.
            anchors.fill: panel
            anchors.rightMargin: panel.edgeOverscan

            // Keeps clicks inside the panel off the outer close-catcher.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: panel.contentInset
                spacing: NotificationTheme.panelSpacing

                // ---- header ----
                // No Clear All button by choice; clearing is reachable over
                // IPC only (see shell.qml).
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

                    // Icon and label dim together, rather than the text
                    // alone, so the placeholder reads as one unit.
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
                        // listPadding stacks on the ColumnLayout's own
                        // panelPadding, so cards sit further in than the labels
                        // above. Each row carries listCardMargin top and
                        // bottom, hence the doubled spacing between them.
                        // Snapped for the same reason as the panel's own
                        // margins: these place each card's 1px outline, which
                        // splits across two columns when it lands off the
                        // device pixel grid.
                        //
                        // The horizontal pair are the last offset before a
                        // card's *text*, so they are solved for where the card
                        // lands rather than snapped on their own: an inset
                        // whole only in device pixels leaves the card on a
                        // fractional logical x, which fringes every glyph in
                        // the list. Both sides take the value solved for the
                        // left edge — where a line of text starts — so the
                        // cards stay centred in the panel. See notes/text.md.
                        readonly property real cardInset: Screens.snapTextInset(NotificationTheme.listPadding, panel.listEdge, panelWindow.screen)
                        spacing: Screens.snap(NotificationTheme.listCardMargin * 2, panelWindow.screen)
                        leftMargin: notificationListView.cardInset
                        rightMargin: notificationListView.cardInset
                        topMargin: Screens.snap(NotificationTheme.listCardMargin, panelWindow.screen)
                        bottomMargin: Screens.snap(NotificationTheme.listCardMargin, panelWindow.screen)
                        model: NotificationService.notificationGroups

                        delegate: NotificationGroupCard {
                            id: listCard
                            required property var modelData
                            // Not `ListView.view.width` alone — that's the
                            // full viewport, so cards overflowed the view's
                            // margins and got clipped.
                            width: ListView.view.width - notificationListView.leftMargin - notificationListView.rightMargin
                            group: listCard.modelData
                            selected: focusScope.selectedKey === listCard.modelData.key
                            // Clicking a row moves the keyboard selection
                            // there too, so the highlight follows the mouse.
                            onSelectRequested: focusScope.selectedKey = listCard.modelData.key
                        }
                    }
                }

                // ---- now playing (mpris) ----
                // Any MPRIS player, not a specific one. MprisService owns
                // selection and paging; this is its view.
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
            }
        }
    }
}
