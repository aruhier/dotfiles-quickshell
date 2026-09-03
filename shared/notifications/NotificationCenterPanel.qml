import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import ".."
import "../../services"
import "../animations"

// swaync's control-center panel: click-triggered (toggled from the bar's
// NotificationCenter indicator via NotificationService.centerOpen), pinned
// open regardless of cursor position — the click-triggered-popup case
// AGENT.md flagged PopupCoordinator as not covering (that coordinator only
// knows one hover-triggered owner at a time). Simplest fix for a single
// panel like this: don't reuse PopupCoordinator at all, just gate visibility
// directly off one singleton bool.
//
// Still just one shared window process-wide (not one per output), but its
// `screen` (set from shell.qml) follows NotificationService.centerScreen,
// which the clicked bar's indicator updates — so it opens on whichever
// output was actually clicked rather than being fixed to the main screen.
//
// Anchored to all 4 screen edges (not just top/right/bottom) so the outer
// MouseArea below can catch an outside click to close — one window instead
// of stacking two layer-shell surfaces, since inter-surface stacking order
// isn't guaranteed. Fully unmapped while closed (`visible` below), so it
// costs nothing and steals no input when not open.
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

    // Kept mapped through the close slide-out, not just while centerOpen is
    // true — unmapping the instant centerOpen flips false would cut the
    // animation off after a single frame.
    //
    // `visible` deliberately does NOT reference NotificationService.centerOpen
    // directly — only `open`/`closing` below, both written together inside
    // one Connections handler. Binding `visible` straight to `centerOpen`
    // (as an earlier version did, `visible: NotificationService.centerOpen ||
    // closing`) raced: that binding and this Connections handler are both
    // independent listeners on the same centerOpenChanged signal, with no
    // guaranteed order between them. When `visible`'s binding happened to
    // re-evaluate first, it read `closing` still false and `centerOpen`
    // already false, so the window briefly unmapped for a frame before the
    // handler ran and remapped it — a real, reproducible "panel disappears
    // for a frame, then reappears and slides" glitch, confirmed via a
    // temporary per-frame console.warn of `anchors.rightMargin` showing the
    // margin itself never jumps (still exactly -2 the instant the close
    // animation starts) — only the window's own mapped state was racing.
    // Routing both `open` and `closing` through the same handler makes them
    // change atomically in program order, so `visible` (downstream of only
    // those two) can never observe an inconsistent combination.
    property bool open: false
    property bool closing: false
    visible: open || closing

    Connections {
        target: NotificationService
        function onCenterOpenChanged() {
            // Order matters: each write below fires its change signal (and
            // any dependent binding re-evaluation, incl. `visible` above)
            // immediately and synchronously — there's no batching across
            // the two statements. Setting `closing` true *before* `open`
            // goes false keeps `open || closing` true at every intermediate
            // point; the previous order (open first) had one JS-tick window
            // where open was already false and closing was still false,
            // which unmapped and remapped the window inside a single
            // signal-handler call — confirmed via a temporary
            // console.warn(visible, Date.now()) that logged both the false
            // and the true transition at the identical millisecond.
            if (!NotificationService.centerOpen)
                panelWindow.closing = true;
            panelWindow.open = NotificationService.centerOpen;
            rightMarginSpring.retarget(NotificationService.centerOpen ? panel.restingRightMargin : panel.closedRightMargin);
        }
    }

    // Generic MPRIS now-playing widget — matches swaync's own mpris widget,
    // which shows whatever's active over MPRIS rather than being tied to
    // MPD specifically, and lets you page between multiple players (swaync
    // shows </> arrows plus pagination dots when more than one is present —
    // confirmed via a live screenshot of the real thing).
    readonly property var mprisPlayers: Mpris.players.values

    // Which player the widget shows. Defaults to whichever's playing (or
    // index 0 if none are) the first time a player list actually exists;
    // after that it's just the user's own </> choice, clamped so it never
    // points past the end of a list that shrank.
    property int mprisIndex: 0
    property bool mprisIndexInitialized: false

    function defaultMprisIndex() {
        for (let i = 0; i < panelWindow.mprisPlayers.length; i++) {
            if (panelWindow.mprisPlayers[i].isPlaying)
                return i;
        }
        return 0;
    }

    onMprisPlayersChanged: {
        if (!mprisIndexInitialized && mprisPlayers.length > 0) {
            mprisIndex = defaultMprisIndex();
            mprisIndexInitialized = true;
        } else if (mprisIndex >= mprisPlayers.length) {
            mprisIndex = Math.max(0, mprisPlayers.length - 1);
        }
    }

    readonly property var activePlayer: mprisPlayers.length > 0 ? mprisPlayers[Math.min(mprisIndex, mprisPlayers.length - 1)] : null

    // Which way the now-playing card's content should slide — read by the
    // slide spring below, set here (not inferred from the index delta)
    // since wraparound at the ends of the list would otherwise make the
    // direction ambiguous.
    property int mprisSlideDirection: 1

    // The player the widget was just showing, captured right before
    // mprisIndex changes below — the now-playing card renders this as a
    // second, non-interactive content layer sliding out while the new
    // activePlayer's content slides in, so a player switch reads as an
    // actual transition between two players' content instead of the single
    // layer just jumping straight to the new data mid-slide.
    property var previousMprisPlayer: null

    // True for exactly the duration of the synchronous mprisIndex write
    // below — Qt property notifies are direct/synchronous, so every
    // dependent binding and change handler downstream of that write (incl.
    // the now-playing card's track-change pop) reacts before the line after
    // it runs. Lets the card tell "track changed because the player was
    // switched" (slide only) apart from "track changed on the same player"
    // (pop only) without a race on which handler happens to fire first.
    property bool suppressMprisPop: false

    function prevMprisPlayer() {
        if (mprisPlayers.length === 0)
            return;
        mprisSlideDirection = -1;
        previousMprisPlayer = activePlayer;
        suppressMprisPop = true;
        mprisIndex = (mprisIndex - 1 + mprisPlayers.length) % mprisPlayers.length;
        suppressMprisPop = false;
    }

    function nextMprisPlayer() {
        if (mprisPlayers.length === 0)
            return;
        mprisSlideDirection = 1;
        previousMprisPlayer = activePlayer;
        suppressMprisPop = true;
        mprisIndex = (mprisIndex + 1) % mprisPlayers.length;
        suppressMprisPop = false;
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    onVisibleChanged: if (visible) {
        focusScope.forceActiveFocus();
        // Pre-select the first row (notification or group) each time the
        // panel opens, rather than carrying a stale index over from the
        // last session or requiring an extra keypress before Up/Down does
        // anything.
        focusScope.selectedIndex = NotificationService.notificationGroups.length > 0 ? 0 : -1;
    }

    // Click-outside-to-close — matches swaync's controlCenter.vala
    // blank_window_gesture.
    MouseArea {
        anchors.fill: parent
        onClicked: NotificationService.closeCenter()
    }

    Item {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: NotificationService.closeCenter()

        // Keyboard selection into NotificationService.notificationGroups —
        // -1 means nothing selected (only reachable once the list empties
        // out from under a selection; the panel otherwise opens pre-selected
        // at 0, see onVisibleChanged above). Up/Down move it, Return/Enter
        // fire the selected row's action (a single notification's default
        // action, or toggle expand/collapse for a group — see
        // activateSelected below), Delete/Backspace dismiss it (the one
        // notification, or every notification in the group).
        property int selectedIndex: -1

        function clampSelection() {
            const len = NotificationService.notificationGroups.length;
            if (focusScope.selectedIndex >= len)
                focusScope.selectedIndex = len - 1;
        }

        // Covers dismissal from any source (keyboard, mouse click on a
        // card's ✕, or Clear All), not just Keys.onDeletePressed below —
        // the list can shrink out from under a keyboard selection whenever
        // the mouse is used at the same time.
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

        // swaync's key_press_event_cb: Return on a single-notification row
        // fires its default action (like clicking the body); on a MANY
        // group it toggles expand/collapse instead.
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
        // No dedicated Keys.onBackspacePressed signal exists (unlike
        // Delete/Return/Enter) — Qt.Key_Back is the browser-style back key,
        // not Backspace, so this has to go through the generic handler.
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

        // The actual panel — left corners rounded only (flush against the
        // right screen edge), same per-corner-radius technique
        // ModuleGroup.qml uses for the bar's own pill shapes.
        //
        // Slides in/out from the right screen edge by animating this same
        // rightMargin between its resting position and fully off-screen
        // (-width, i.e. the panel's own width past the edge) instead of
        // toggling visible directly — visible itself just tracks
        // panelWindow.closing so the window stays mapped for the full
        // slide-out.
        //
        // The resting value -2 (not 0) is a deliberate 2px overscan past
        // the window's true right edge, not a bug. On this machine's DP-1
        // (Hyprland scale: 1.25) a rightMargin of exactly 0 left the true
        // last physical column of the screen transparent — panelWindow's
        // own background is "transparent" (only this child Rectangle
        // paints anything), and at that fractional scale the compositor's
        // scaling of the surface buffer doesn't reliably cover its own
        // last device pixel. Bar.qml doesn't hit this because its
        // background comes from the *window's own* `color`, not a child
        // item. Confirmed via pixel-level screenshot diffing (see
        // AGENT.md) that -2 fully closes the gap at every row; the extra
        // 2px are square (no corner radius on this side) and land past
        // the true screen edge, so the compositor clips them — no visible
        // difference vs. 0 other than the gap being gone. The fully-closed
        // value below is offset by the same -2 for consistency, though it
        // barely matters off-screen.
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

            // FrameSpring, not Behavior/SpringAnimation — this panel lives
            // on DP-1 (240Hz), and Behavior-based SpringAnimation visibly
            // stutters there because it rides Qt Quick's shared
            // QUnifiedTimer clock, fixed at ~60Hz regardless of the
            // output's real refresh rate. FrameSpring ticks off
            // FrameAnimation instead, which fires once per actual rendered
            // frame — see its header comment and AGENT.md's "capped near
            // 60Hz" section for the empirical diagnosis. Not declarative
            // like Behavior: retarget() is called explicitly from the
            // Connections handler above whenever centerOpen changes.
            FrameSpring {
                id: rightMarginSpring
                // Softer than Theme.frameSpring{Stiffness,Damping,Mass}
                // (460/35/0.6, ~137ms settle) — those are shared with other
                // modules' width-change springs, so overridden here rather
                // than changed globally. Same zeta (~1.05, near-critical —
                // still no wobble), just a lower natural frequency: ~185ms
                // settle instead, a deliberately slower open/close slide for
                // this panel specifically (a first pass at 140/19 settled in
                // ~250ms — this splits the difference between that and the
                // original 460/35).
                stiffness: 160
                damping: 18
                Component.onCompleted: snapTo(panel.closedRightMargin)
                onRunningChanged: if (!running && !NotificationService.centerOpen)
                    panelWindow.closing = false
            }

            color: NotificationTheme.bgGlobal
            border.width: 1
            border.color: Qt.rgba(NotificationTheme.text.r, NotificationTheme.text.g, NotificationTheme.text.b, 0.1)
            topLeftRadius: NotificationTheme.controlCenterRadius
            bottomLeftRadius: NotificationTheme.controlCenterRadius
            topRightRadius: 0
            bottomRightRadius: 0

            // Consumes clicks inside the panel so they don't fall through
            // to the outer close-catcher (ordinary QtQuick z-order
            // consumption — this Rectangle is drawn after/above the outer
            // MouseArea, so hit-testing never reaches it for clicks in
            // here).
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // ---- header ----
                // No Clear All button here — config.json's title widget has
                // clear-all-button: false, and the separate "inhibitors"
                // widget (which owns the other clear-all-button) isn't in
                // the configured `widgets` list at all. Confirmed against a
                // live swaync screenshot: no button anywhere in the panel.
                // Clearing is still reachable via the `notifications clear`
                // IPC call (see shell.qml), just not from this UI.
                Text {
                    renderType: Text.NativeRendering
                    text: "Notifications"
                    color: NotificationTheme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: NotificationTheme.fontSize + 2
                    font.bold: true
                }

                // ---- DND ----
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        renderType: Text.NativeRendering
                        Layout.fillWidth: true
                        text: "Do Not Disturb"
                        color: NotificationTheme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: NotificationTheme.fontSize
                    }

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 22
                        radius: height / 2
                        color: NotificationService.dnd ? NotificationTheme.bgSelected : NotificationTheme.bg
                        border.width: NotificationService.dnd ? 0 : 1
                        border.color: NotificationTheme.borderColor

                        Rectangle {
                            width: parent.height - 4
                            height: parent.height - 4
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: NotificationService.dnd ? parent.width - width - 2 : 2
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

                        Text {
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignHCenter
                            text: "No Notifications"
                            color: NotificationTheme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: NotificationTheme.fontSize
                        }
                    }

                    ListView {
                        id: notificationListView
                        anchors.fill: parent
                        clip: true
                        // swaync's style.css: `.notification { margin: 6px
                        // 12px }` — matched here as spacing (vertical gap
                        // between cards) + left/rightMargin (horizontal
                        // gutter), rather than the bare 2px this had before,
                        // which read as cramped against the panel edges.
                        spacing: 10
                        leftMargin: 12
                        rightMargin: 12
                        model: NotificationService.notificationGroups

                        delegate: NotificationGroupCard {
                            id: listCard
                            required property var modelData
                            required property int index
                            // Not `ListView.view.width` alone — that's the
                            // full viewport, which ignores the view's own
                            // left/rightMargin above and made every card
                            // (and its selection border) overflow the
                            // margin and get clipped by `clip: true`,
                            // visible as a glitchy seam on the right edge of
                            // the selected card once the margin grew beyond
                            // a pixel or two.
                            width: ListView.view.width - notificationListView.leftMargin - notificationListView.rightMargin
                            group: modelData
                            selected: focusScope.selectedIndex === index
                        }
                    }
                }

                // ---- now playing (mpris) ----
                // Generic MPRIS widget, like swaync's own — whatever's
                // active over MPRIS (see panelWindow.activePlayer above),
                // not tied to any specific player. Sits on its own rounded
                // card and gets </> paging + dots once a second player
                // shows up, and shuffle/repeat controls alongside
                // prev/play/next — all matching a live swaync screenshot of
                // this same widget.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: panelWindow.activePlayer !== null
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            renderType: Text.NativeRendering
                            visible: panelWindow.mprisPlayers.length > 1
                            text: "󰅁"
                            color: NotificationTheme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: NotificationTheme.mprisControlIconSize - 4
                            scale: prevPlayerPress.value

                            PressSpring {
                                id: prevPlayerPress
                                pressed: prevPlayerArea.pressed
                            }

                            MouseArea {
                                id: prevPlayerArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panelWindow.prevMprisPlayer()
                            }
                        }

                        Rectangle {
                            id: mprisCard
                            Layout.fillWidth: true
                            Layout.preferredHeight: incomingContent.implicitHeight + 24
                            radius: 14
                            color: NotificationTheme.bgHover
                            scale: mprisPopSpring.value

                            // Switching player (prev/next arrows, or the
                            // list shrinking out from under mprisIndex): the
                            // card itself stays put — only its content (the
                            // clipped layer below, sized to mprisClip.width)
                            // slides — panelWindow.mprisSlideDirection is
                            // set by prevMprisPlayer/nextMprisPlayer right
                            // before this index write, not inferred from the
                            // delta, since wraparound at the ends of the
                            // list makes the delta's sign ambiguous.
                            readonly property int watchedIndex: panelWindow.mprisIndex
                            onWatchedIndexChanged: {
                                mprisSlideSpring.value = panelWindow.mprisSlideDirection * mprisClip.width;
                                mprisSlideSpring.retarget(0);
                            }

                            // Same player, new track (e.g. the song simply
                            // advanced): a small scale bounce instead, same
                            // spring feedback a new notification popping in
                            // gets. Suppressed for the one change that
                            // happens as a side effect of switching players
                            // above — that gets the slide instead, so the
                            // two effects never stack on the same
                            // transition.
                            readonly property string trackKey: panelWindow.activePlayer ? panelWindow.activePlayer.trackTitle + "|" + panelWindow.activePlayer.trackArtist : ""
                            onTrackKeyChanged: {
                                if (panelWindow.suppressMprisPop)
                                    return;
                                mprisPopSpring.value = 0.94;
                                mprisPopSpring.retarget(1);
                            }

                            FrameSpring {
                                id: mprisPopSpring
                                value: 1
                                target: 1
                                // See PressSpring.qml's comment — the
                                // default epsilon is tuned for pixel-scale
                                // springs, too coarse for this 0..1 scale
                                // bump (1 -> 0.94).
                                epsilon: 0.002
                            }

                            // Drives both content layers' x below — full
                            // card-width travel now (a real page swap, not a
                            // small nudge), so it needs to be slow enough to
                            // actually read as motion across that distance.
                            // A mass-spring-damper's settle time is
                            // independent of the distance travelled, so the
                            // same stiffness/damping works regardless of how
                            // wide the card ends up. stiffness=110/damping=16
                            // (mass=1) gives zeta ~0.76 — a bit lighter than
                            // critical (1.0, the previous value), so there's
                            // a small bit of give/overshoot at the end
                            // rather than gliding to a dead stop, and a
                            // ~0.50s settle instead of ~0.61s. Confirmed
                            // still well clear of the too-wobbly zeta ~0.64
                            // this had at one point.
                            FrameSpring {
                                id: mprisSlideSpring
                                value: 0
                                target: 0
                                stiffness: 60
                                damping: 13
                                mass: 0.8
                            }

                            // Clips the two sliding content layers to the
                            // card's own content area — without this,
                            // whichever layer is mid-slide would spill out
                            // past the card's rounded edges instead of
                            // looking like a page swapping inside a fixed
                            // frame.
                            Item {
                                id: mprisClip
                                anchors.fill: parent
                                anchors.margins: 12
                                clip: true

                                // Outgoing: the player this widget was just
                                // showing, sliding out the opposite side
                                // from the one the incoming layer slides in
                                // from. Only actually on-screen for the
                                // duration of the slide (mprisSlideSpring
                                // running) — interactive: false the whole
                                // time regardless, since it's on its way out
                                // and shouldn't answer clicks meant for the
                                // incoming layer.
                                MprisNowPlayingContent {
                                    width: mprisClip.width
                                    height: mprisClip.height
                                    visible: mprisSlideSpring.running && panelWindow.previousMprisPlayer !== null
                                    player: panelWindow.previousMprisPlayer
                                    interactive: false
                                    x: mprisSlideSpring.value - panelWindow.mprisSlideDirection * mprisClip.width
                                }

                                // Incoming: the current activePlayer, always
                                // the interactive layer. Starts offset by a
                                // full card-width in the direction it's
                                // "coming from" and slides to x: 0 as
                                // mprisSlideSpring settles.
                                MprisNowPlayingContent {
                                    id: incomingContent
                                    width: mprisClip.width
                                    height: mprisClip.height
                                    player: panelWindow.activePlayer
                                    x: mprisSlideSpring.value
                                }
                            }
                        }

                        Text {
                            renderType: Text.NativeRendering
                            visible: panelWindow.mprisPlayers.length > 1
                            text: "󰅂"
                            color: NotificationTheme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: NotificationTheme.mprisControlIconSize - 4
                            scale: nextPlayerPress.value

                            PressSpring {
                                id: nextPlayerPress
                                pressed: nextPlayerArea.pressed
                            }

                            MouseArea {
                                id: nextPlayerArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panelWindow.nextMprisPlayer()
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: panelWindow.mprisPlayers.length > 1
                        spacing: 6

                        Repeater {
                            model: panelWindow.mprisPlayers.length

                            Rectangle {
                                required property int index
                                width: 6
                                height: 6
                                radius: 3
                                color: index === panelWindow.mprisIndex ? NotificationTheme.text : NotificationTheme.textDisabled
                            }
                        }
                    }
                }
            }
        }

        // Matches swaync's `.control-center { box-shadow: 0px 1px 12px 1px
        // rgba(0, 0, 0, 0.4) }` (~/dotfiles/swaync/style.css) — same
        // MultiEffect-as-source pattern as NotificationCard.qml's
        // background/shadow pair.
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
