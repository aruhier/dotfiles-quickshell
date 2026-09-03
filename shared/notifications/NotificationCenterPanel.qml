import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import ".."
import "../../services"

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
    visible: NotificationService.centerOpen

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
        // rightMargin: -2 (not 0) is a deliberate 2px overscan past the
        // window's true right edge, not a bug. On this machine's DP-1
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
        // difference vs. 0 other than the gap being gone.
        Rectangle {
            id: panel
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: NotificationTheme.controlCenterMarginV
            anchors.rightMargin: -2
            width: NotificationTheme.controlCenterWidth

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
