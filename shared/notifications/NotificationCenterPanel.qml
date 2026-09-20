pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
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
    // flush margin leaves transparent at fractional scale is covered. Must
    // stay clear of ControlCenterSlide's bump; see notes/panels.md.
    readonly property int overscan: 22
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

        // Slides in and out by animating rightMargin, rather than toggling
        // visibility; the gesture itself is ControlCenterSlide.qml.
        //
        // The plate is drawn `edgeOverscan` wider than it reads and rests that
        // far past the screen edge. That slack is what the arrival's bump pulls
        // in, instead of opening a gap to the edge, and it also covers the last
        // physical column, which a flush margin leaves transparent at
        // fractional scale since only this Rectangle paints. The side past the
        // edge is square, and compositor-clipped.
        //
        // Every *resting* offset placing this Rectangle goes through
        // `Screens.snap()`, width included — it is right-anchored, so margin
        // and width together decide where the left edge lands, and this
        // Rectangle's own 1px border draws as two half-lit columns off the
        // device pixel grid. Mid-gesture it is deliberately off that grid; see
        // ControlCenterSlide.qml. The panel's *text* needs more than this — see
        // `listEdge` below and notes/text.md — and needed getting out of the
        // shadow's layer, below.
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

        // Everything the panel *shows* lives here, a sibling of the shadow's
        // source rather than a child of it, so `panel` stays an empty
        // background plate. A source item is rendered into a layer texture and
        // that texture is drawn with linear filtering, so whenever the item
        // lands on a fraction of a device pixel — routine at fractional scale
        // — the whole subtree inside it is resampled. Qt rounds glyph
        // positions for ordinary items, so unlayered text is immune at any
        // offset; text *inside* a layer is not, and this panel used to put its
        // entire contents in one. Measured: notes/text.md.
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
