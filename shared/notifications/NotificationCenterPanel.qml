pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.shared
import qs.services
import qs.shared.notifications
import qs.themes

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

    // Gap above and below the panel, so it floats rather than filling the edge.
    readonly property int marginV: 50
    // Drawn past the right screen edge, on top of NotificationTheme.controlCenterWidth: the
    // panel is this much wider than it reads, so its opening bump slides that
    // slack in rather than opening a gap to the edge, and the edge column a
    // flush margin leaves transparent at fractional scale is covered. Sized
    // off both of ControlCenterSlide's bumps; see notes/panels.md.
    readonly property int overscan: Math.ceil(slide.reach)
    // The DND switch: 48x29 with a 20px slider.
    readonly property int switchWidth: 48
    readonly property int switchHeight: 29
    readonly property int switchPadding: 4

    Connections {
        target: NotificationService
        function onCenterOpenChanged() {
            // Writes fire their signals synchronously and unbatched, so
            // `closing` must be set before `open` clears to keep `open ||
            // closing` true at every intermediate point.
            if (!NotificationService.centerOpen)
                panelWindow.closing = true;
            panelWindow.open = NotificationService.centerOpen;
            // `closing` is cleared here, not only when the exit finishes,
            // so that reopening mid-close does not leave the window pinned
            // visible. Ordered after the write above so `open || closing`
            // never dips false.
            if (NotificationService.centerOpen) {
                panelWindow.closing = false;
                slide.open();
            } else {
                slide.close();
            }
        }
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    // Tied to centerOpen, not visible: focus returns underneath the instant
    // the user closes, not once the slide-out spring settles.
    WlrLayershell.keyboardFocus: NotificationService.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // A closing panel takes no input. The full-screen surface stays mapped
    // for the slide-out (~600ms), and without this the click-outside area
    // below kept swallowing clicks meant for the window underneath for that
    // long, each a no-op closeCenter(). Null is "the whole window", as it must
    // be while open for that area to work.
    mask: panelWindow.closing ? closingMask : null
    readonly property Region closingMask: Region {}

    function takeFocus() {
        focusScope.forceActiveFocus();
        // Pre-select the first row, so Up/Down works without a priming press.
        focusScope.selectedKey = NotificationService.notificationGroups.length > 0 ? NotificationService.notificationGroups[0].key : "";
    }

    onVisibleChanged: if (visible)
        takeFocus()

    // Moved to another output while open (another screen's bell clicked):
    // the window stays visible, so neither handler above runs. Arrive there
    // as on an open, and take focus again on the new surface.
    onScreenChanged: if (panelWindow.open) {
        slide.reopen();
        takeFocus();
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
        readonly property var selectedGroup: focusScope.selectedIndex >= 0 ? NotificationService.notificationGroups[focusScope.selectedIndex] : null

        // So dismissing the selected group lands the selection on whatever
        // slid up into that row rather than dropping it.
        property int lastSelectedIndex: 0
        onSelectedIndexChanged: if (focusScope.selectedIndex >= 0)
            focusScope.lastSelectedIndex = focusScope.selectedIndex

        // Covers dismissal from any source: the mouse can shrink the list out
        // from under a keyboard selection. On the groups' signal, not
        // `notifications`': the service updates `notifications` first, and a
        // handler on that still sees the dismissed group listed.
        Connections {
            target: NotificationService
            function onNotificationGroupsChanged() {
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
            const group = focusScope.selectedGroup;
            if (!group)
                return;
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
            if (!focusScope.selectedGroup)
                return;
            // Through the row, so it plays its exit gesture; a row scrolled far
            // enough out of the view has no delegate to ask.
            const row = notificationListView.itemAtIndex(focusScope.selectedIndex) as NotificationGroupCard;
            if (row)
                row.dismiss();
            else
                NotificationService.dismissGroup(focusScope.selectedGroup);
        }

        // Slides by animating rightMargin (ControlCenterSlide.qml), drawn
        // `edgeOverscan` wider than it reads so neither bump shows its edge
        // (notes/panels.md). Every resting offset, width included, goes
        // through Screens.snap() so the 1px border lands on the device grid;
        // the text needs more than that — `listEdge` below, notes/text.md.
        Rectangle {
            id: panel
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Screens.snap(panelWindow.marginV, panelWindow.screen)
            anchors.rightMargin: slide.margin
            // Snapped separately and added, rather than snapping the sum: the
            // left edge lands at `width - edgeOverscan`, so both have to be on
            // the device pixel grid for it to be.
            readonly property real visibleWidth: Screens.snap(NotificationTheme.controlCenterWidth, panelWindow.screen)
            readonly property real edgeOverscan: Screens.snap(panelWindow.overscan, panelWindow.screen)
            width: panel.visibleWidth + panel.edgeOverscan

            readonly property real restingRightMargin: -panel.edgeOverscan
            // Off-screen, so it only has to clear the edge, not land on it.
            readonly property real closedRightMargin: -panel.width - 2

            // The panel's inner inset, and where the list's left edge sits in
            // the window once the panel is at rest. The card inset is solved
            // against this rather than snapped on its own: what a text subtree
            // needs is a whole logical landing place, and where that is
            // depends on where the panel has landed on this output. Off the
            // *resting* geometry and never the live x — re-solving it
            // mid-slide would walk the list sideways inside the panel.
            readonly property real contentInset: Screens.snap(NotificationTheme.panelPadding, panelWindow.screen)
            readonly property real listEdge: panelWindow.width - panel.visibleWidth + panel.contentInset

            // Driven imperatively from the Connections handler above; the
            // staging, the latches and the tuning live in the gesture.
            ControlCenterSlide {
                id: slide
                resting: panel.restingRightMargin
                closed: panel.closedRightMargin
                screen: panelWindow.screen
                onFinished: panelWindow.closing = false
            }

            color: NotificationTheme.bgGlobal
            border.width: 1
            border.color: NotificationTheme.borderSubtle
            topLeftRadius: NotificationTheme.controlCenterRadius
            bottomLeftRadius: NotificationTheme.controlCenterRadius
            topRightRadius: 0
            bottomRightRadius: 0
        }

        DropShadow {
            source: panel
        }

        // Everything the panel shows lives here, a sibling of the shadow's
        // source, not a child: a layer is resampled at fractional offsets and
        // blurs the text inside it, unlayered text isn't. notes/text.md.
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
                // IPC only (see Ipc.qml).
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
                        Layout.preferredWidth: panelWindow.switchWidth
                        Layout.preferredHeight: panelWindow.switchHeight
                        radius: height / 2
                        color: NotificationService.dnd ? NotificationTheme.bgSelected : NotificationTheme.bg
                        border.width: NotificationService.dnd ? 0 : 1
                        border.color: NotificationTheme.borderColor

                        Rectangle {
                            width: parent.height - panelWindow.switchPadding * 2
                            height: parent.height - panelWindow.switchPadding * 2
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: NotificationService.dnd ? parent.width - width - panelWindow.switchPadding : panelWindow.switchPadding
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

                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: 64
                            color: NotificationTheme.text
                            text: "󱉴"
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
                        // Each row carries listCardMargin top and bottom, hence
                        // the doubled spacing; snapped so card outlines stay
                        // crisp. The horizontal inset is solved for where the
                        // card's text lands, both sides from the left edge so
                        // cards stay centred. See notes/text.md.
                        readonly property real cardInset: Screens.snapTextInset(NotificationTheme.listPadding, panel.listEdge, panelWindow.screen)
                        spacing: Screens.snap(NotificationTheme.listCardMargin * 2, panelWindow.screen)
                        leftMargin: notificationListView.cardInset
                        rightMargin: notificationListView.cardInset
                        topMargin: Screens.snap(NotificationTheme.listCardMargin, panelWindow.screen)
                        bottomMargin: Screens.snap(NotificationTheme.listCardMargin, panelWindow.screen)
                        model: NotificationService.groupModel

                        // The model's `group` role fills the card's required
                        // property of that name.
                        delegate: NotificationGroupCard {
                            id: listCard
                            // Not `ListView.view.width` alone — that's the
                            // full viewport, so cards overflowed the view's
                            // margins and got clipped.
                            width: ListView.view.width - notificationListView.leftMargin - notificationListView.rightMargin
                            selected: focusScope.selectedKey === listCard.group.key
                            // Clicking a row moves the keyboard selection
                            // there too, so the highlight follows the mouse.
                            onSelectRequested: focusScope.selectedKey = listCard.group.key
                        }
                    }
                }

                // ---- now playing (mpris) ----
                MprisNowPlayingWidget {
                }
            }
        }
    }
}
