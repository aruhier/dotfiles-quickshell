import QtQuick
import QtQuick.Layouts
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

    function prevMprisPlayer() {
        if (mprisPlayers.length === 0)
            return;
        mprisIndex = (mprisIndex - 1 + mprisPlayers.length) % mprisPlayers.length;
    }

    function nextMprisPlayer() {
        if (mprisPlayers.length === 0)
            return;
        mprisIndex = (mprisIndex + 1) % mprisPlayers.length;
    }

    // Cycles the active player's loop mode the same order swaync's own
    // repeat button does: off -> playlist -> track -> off.
    function cycleLoopState() {
        const p = panelWindow.activePlayer;
        if (!p)
            return;
        if (p.loopState === MprisLoopState.None)
            p.loopState = MprisLoopState.Playlist;
        else if (p.loopState === MprisLoopState.Playlist)
            p.loopState = MprisLoopState.Track;
        else
            p.loopState = MprisLoopState.None;
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    onVisibleChanged: if (visible) {
        focusScope.forceActiveFocus();
        // Start unselected each time the panel opens rather than carrying
        // a stale index over from the last session.
        focusScope.selectedIndex = -1;
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

        // Keyboard selection into NotificationService.notifications — -1
        // means nothing selected. Up/Down move it, Return/Enter fire the
        // selected card's default action (same as clicking its body),
        // Delete/Backspace dismiss it (same as clicking its ✕).
        property int selectedIndex: -1

        function clampSelection() {
            const len = NotificationService.notifications.length;
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
            if (NotificationService.notifications.length === 0)
                return;
            focusScope.selectedIndex = focusScope.selectedIndex <= 0 ? 0 : focusScope.selectedIndex - 1;
            notificationListView.positionViewAtIndex(focusScope.selectedIndex, ListView.Contain);
        }

        Keys.onDownPressed: {
            const len = NotificationService.notifications.length;
            if (len === 0)
                return;
            focusScope.selectedIndex = focusScope.selectedIndex < 0 ? 0 : Math.min(focusScope.selectedIndex + 1, len - 1);
            notificationListView.positionViewAtIndex(focusScope.selectedIndex, ListView.Contain);
        }

        Keys.onReturnPressed: focusScope.activateSelected()
        Keys.onEnterPressed: focusScope.activateSelected()

        function activateSelected() {
            const list = NotificationService.notifications;
            if (focusScope.selectedIndex < 0 || focusScope.selectedIndex >= list.length)
                return;
            const wrapper = list[focusScope.selectedIndex];
            if (wrapper.defaultAction)
                wrapper.defaultAction.invoke();
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
            const list = NotificationService.notifications;
            if (focusScope.selectedIndex < 0 || focusScope.selectedIndex >= list.length)
                return;
            NotificationService.dismiss(list[focusScope.selectedIndex]);
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

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        visible: NotificationService.notifications.length === 0
                        text: "No notifications"
                        color: NotificationTheme.textDisabled
                        font.family: Theme.fontFamily
                        font.pixelSize: NotificationTheme.fontSize
                    }

                    ListView {
                        id: notificationListView
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        leftMargin: 2
                        rightMargin: 2
                        model: NotificationService.notifications

                        delegate: NotificationCard {
                            id: listCard
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            wrapper: modelData
                            floating: false
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

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panelWindow.prevMprisPlayer()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: mprisContent.implicitHeight + 24
                            radius: 14
                            color: NotificationTheme.bgHover

                            RowLayout {
                                id: mprisContent
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 14

                                ClippingRectangle {
                                    Layout.preferredWidth: NotificationTheme.mprisImageSize
                                    Layout.preferredHeight: NotificationTheme.mprisImageSize
                                    radius: NotificationTheme.mprisImageRadius
                                    color: NotificationTheme.bg

                                    Image {
                                        anchors.fill: parent
                                        visible: panelWindow.activePlayer && panelWindow.activePlayer.trackArtUrl !== ""
                                        source: panelWindow.activePlayer ? panelWindow.activePlayer.trackArtUrl : ""
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
                                        text: panelWindow.activePlayer ? panelWindow.activePlayer.trackTitle : ""
                                        color: NotificationTheme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: NotificationTheme.mprisTitleFontSize
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        Layout.fillWidth: true
                                        text: panelWindow.activePlayer ? panelWindow.activePlayer.trackArtist : ""
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
                                            color: panelWindow.activePlayer && panelWindow.activePlayer.shuffleSupported ? (panelWindow.activePlayer.shuffle ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                                            font.family: Theme.fontFamily
                                            font.pixelSize: NotificationTheme.mprisControlIconSize - 4

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: panelWindow.activePlayer && panelWindow.activePlayer.shuffleSupported
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panelWindow.activePlayer.shuffle = !panelWindow.activePlayer.shuffle
                                            }
                                        }

                                        Text {
                                            renderType: Text.NativeRendering
                                            text: "󰒮"
                                            color: panelWindow.activePlayer && panelWindow.activePlayer.canGoPrevious ? NotificationTheme.text : NotificationTheme.textDisabled
                                            font.family: Theme.fontFamily
                                            font.pixelSize: NotificationTheme.mprisControlIconSize

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: panelWindow.activePlayer && panelWindow.activePlayer.canGoPrevious
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panelWindow.activePlayer.previous()
                                            }
                                        }

                                        Text {
                                            renderType: Text.NativeRendering
                                            text: panelWindow.activePlayer && panelWindow.activePlayer.isPlaying ? "󰏤" : "󰐊"
                                            color: panelWindow.activePlayer && panelWindow.activePlayer.canTogglePlaying ? NotificationTheme.text : NotificationTheme.textDisabled
                                            font.family: Theme.fontFamily
                                            font.pixelSize: NotificationTheme.mprisControlIconSize

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: panelWindow.activePlayer && panelWindow.activePlayer.canTogglePlaying
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panelWindow.activePlayer.togglePlaying()
                                            }
                                        }

                                        Text {
                                            renderType: Text.NativeRendering
                                            text: "󰒭"
                                            color: panelWindow.activePlayer && panelWindow.activePlayer.canGoNext ? NotificationTheme.text : NotificationTheme.textDisabled
                                            font.family: Theme.fontFamily
                                            font.pixelSize: NotificationTheme.mprisControlIconSize

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: panelWindow.activePlayer && panelWindow.activePlayer.canGoNext
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panelWindow.activePlayer.next()
                                            }
                                        }

                                        Text {
                                            renderType: Text.NativeRendering
                                            text: panelWindow.activePlayer && panelWindow.activePlayer.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                                            color: panelWindow.activePlayer && panelWindow.activePlayer.loopSupported ? (panelWindow.activePlayer.loopState !== MprisLoopState.None ? NotificationTheme.bgSelected : NotificationTheme.text) : NotificationTheme.textDisabled
                                            font.family: Theme.fontFamily
                                            font.pixelSize: NotificationTheme.mprisControlIconSize - 4

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: panelWindow.activePlayer && panelWindow.activePlayer.loopSupported
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panelWindow.cycleLoopState()
                                            }
                                        }
                                    }
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

                            MouseArea {
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
    }
}
