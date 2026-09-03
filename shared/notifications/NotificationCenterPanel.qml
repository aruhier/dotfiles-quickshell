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
    // MPD specifically. Prefers a currently-playing player, falling back to
    // the first available one (e.g. paused) so the widget doesn't blink
    // away between tracks.
    readonly property var mprisPlayers: Mpris.players.values
    readonly property var activePlayer: {
        for (const p of mprisPlayers) {
            if (p.isPlaying)
                return p;
        }
        return mprisPlayers.length > 0 ? mprisPlayers[0] : null;
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    onVisibleChanged: if (visible)
        focusScope.forceActiveFocus()

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
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        renderType: Text.NativeRendering
                        text: "Notifications"
                        color: NotificationTheme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: clearAllLabel.implicitWidth + 20
                        Layout.preferredHeight: 26
                        radius: 10
                        color: clearAllArea.containsMouse ? NotificationTheme.bgHover : NotificationTheme.bg
                        border.width: 1
                        border.color: NotificationTheme.borderColor

                        Text {
                            id: clearAllLabel
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "Clear All"
                            color: NotificationTheme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        MouseArea {
                            id: clearAllArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.clearAll()
                        }
                    }
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
                        font.pixelSize: Theme.fontSize
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
                        font.pixelSize: Theme.fontSize
                    }

                    ListView {
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        leftMargin: 2
                        rightMargin: 2
                        model: NotificationService.notifications

                        delegate: NotificationCard {
                            id: listCard
                            required property var modelData
                            width: ListView.view.width
                            wrapper: modelData
                            floating: false
                        }
                    }
                }

                // ---- now playing (mpris) ----
                // Generic MPRIS widget, like swaync's own — whatever's
                // active over MPRIS (see panelWindow.activePlayer above),
                // not tied to any specific player.
                RowLayout {
                    Layout.fillWidth: true
                    visible: panelWindow.activePlayer !== null
                    spacing: 10

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
                        spacing: 2

                        Text {
                            renderType: Text.NativeRendering
                            Layout.fillWidth: true
                            text: panelWindow.activePlayer ? panelWindow.activePlayer.trackTitle : ""
                            color: NotificationTheme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            Layout.fillWidth: true
                            text: panelWindow.activePlayer ? panelWindow.activePlayer.trackArtist : ""
                            color: NotificationTheme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            spacing: 14

                            Text {
                                renderType: Text.NativeRendering
                                text: "󰒮"
                                color: panelWindow.activePlayer && panelWindow.activePlayer.canGoPrevious ? NotificationTheme.text : NotificationTheme.textDisabled
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconFontSize

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
                                font.pixelSize: Theme.iconFontSize

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
                                font.pixelSize: Theme.iconFontSize

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: panelWindow.activePlayer && panelWindow.activePlayer.canGoNext
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panelWindow.activePlayer.next()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
