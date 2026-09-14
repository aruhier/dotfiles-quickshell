pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Wayland
import qs.shared
import qs.services
import qs.shared.animations
import qs.shared.notifications

// The toast stack, in the top-right corner under the bar. Anchored to the
// screen, not to a module, so it's a plain PanelWindow rather than the
// module-anchored machinery in ../popup/. One shared window whose `screen`
// follows NotificationService.popupScreen.
PanelWindow {
    id: popupWindow

    anchors {
        top: true
        right: true
    }
    // Snapped to the device pixel grid, like the control center's margins: an
    // off-grid margin puts the stack on a fraction of a device pixel and every
    // glyph in it renders smeared. See NotificationCenterPanel.qml.
    margins.top: Screens.snap(Theme.barHeight + 10, popupWindow.screen)
    // The gap to the screen edge is room *inside* the surface, not a
    // layer-shell margin: the plate springs past its full width as it opens,
    // and a window clips its contents.
    margins.right: 0
    readonly property real edgeGap: Screens.snap(10, popupWindow.screen)

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Fully unmapped while empty, so no stray surface eats input. Tracks
    // displayPopupsModel, not NotificationService.popups, so the window
    // outlives the last card's exit spring.
    visible: displayPopupsModel.count > 0

    // The surface is wider than the stack on both sides, and a toast is
    // clickable — without this the slack either side would swallow clicks
    // meant for whatever is under it, the screen's own right edge included.
    mask: Region {
        item: column
    }

    // Widest popup's naturalWidth (see NotificationCard.qml): most toasts sit
    // at the minimum, a long summary pushes the stack towards popupMaxWidth.
    readonly property real maxNaturalWidth: {
        let w = 0;
        for (let i = 0; i < popupRepeater.count; i++) {
            const item = popupRepeater.itemAt(i);
            if (item)
                w = Math.max(w, item.naturalWidth);
        }
        return w;
    }

    // The cards' own width. Snapped for the same reason as the margins: the
    // stack is right-anchored, so this is what decides where its left edge —
    // and with it every card's text — lands on the device pixel grid.
    // maxNaturalWidth is a measured implicitWidth, so it is rarely integral.
    readonly property real stackWidth: Screens.snap(Math.min(Math.max(maxNaturalWidth, NotificationTheme.popupMinWidth), NotificationTheme.popupMaxWidth), popupWindow.screen)

    // The stack, the gap it keeps from the screen edge — which is also what the
    // opening plate springs past its full width into — and slack on the far
    // side for the slide to overshoot into. See NotificationTheme.popupOvershoot.
    implicitWidth: Screens.snap(NotificationTheme.popupOvershoot + stackWidth + edgeGap, popupWindow.screen)
    implicitHeight: column.implicitHeight

    // One entry per popup on screen: a superset of NotificationService.popups
    // that keeps a dismissed entry (closing: true) for the length of its exit
    // spring, since Repeater destroys a delegate the instant its row leaves
    // the model (see removeDisplayPopup).
    //
    // `display` snapshots the wrapper's fields once, on creation, and the card
    // binds to that instead of the wrapper: an app closing its own
    // notification over D-Bus can free it out from under a live binding, and
    // Retainable.lock() doesn't cover that path — a burst of them logged a
    // page of null-property errors.
    component PopupEntry: QtObject {
        required property var wrapper
        property bool closing: false
        property var display: null

        Component.onCompleted: display = {
            "summary": wrapper.summary,
            "body": wrapper.body,
            "appName": wrapper.appName,
            "appIcon": wrapper.appIcon,
            "image": wrapper.image,
            "urgency": wrapper.urgency,
            "timeStr": wrapper.timeStr,
            "defaultAction": wrapper.defaultAction,
            "otherActions": wrapper.otherActions,
            // Not displayed — carried so the card's dismiss paths still have
            // something to dismiss. Only reachable while `interactive`.
            "notification": wrapper.notification
        }
    }

    // ListModel, not a list property reassigned by spread: a whole-array
    // reassignment makes Repeater recreate every delegate, and doing that
    // reentrantly (a notification arriving mid-incubation) segfaults in
    // QQuickRepeater::regenerate(). append()/remove() are incremental.
    ListModel {
        id: displayPopupsModel
    }

    property Component popupEntryComponent: Component {
        PopupEntry {}
    }

    function indexOfWrapper(w) {
        for (let i = 0; i < displayPopupsModel.count; i++) {
            if (displayPopupsModel.get(i).entry.wrapper === w)
                return i;
        }
        return -1;
    }

    function syncDisplayPopups() {
        const live = NotificationService.popups;

        for (const w of live) {
            if (indexOfWrapper(w) !== -1)
                continue;
            displayPopupsModel.append({
                "entry": popupEntryComponent.createObject(popupWindow, {
                    "wrapper": w
                })
            });
        }

        for (let i = 0; i < displayPopupsModel.count; i++) {
            const entry = displayPopupsModel.get(i).entry;
            if (!entry.closing && live.indexOf(entry.wrapper) === -1)
                entry.closing = true;
        }
    }

    // `index` is the delegate's live Repeater index, not one captured at
    // creation, so it stays right as rows are added and removed.
    function removeDisplayPopup(index, entry) {
        displayPopupsModel.remove(index);
        entry.destroy();
    }

    Connections {
        target: NotificationService
        function onPopupsChanged() {
            popupWindow.syncDisplayPopups();
        }
    }

    Component.onCompleted: popupWindow.syncDisplayPopups()

    Column {
        id: column
        anchors.right: parent.right
        anchors.rightMargin: popupWindow.edgeGap
        width: popupWindow.stackWidth
        spacing: 8

        Repeater {
            id: popupRepeater
            model: displayPopupsModel

            Item {
                id: entryRoot
                required property var entry
                required property int index

                readonly property alias naturalWidth: card.naturalWidth

                width: column.width
                implicitHeight: card.implicitHeight

                // Entry and exit are staged, off spring values rather than
                // timers, the way the OSD pill is — the icon alone slides in
                // from the right, the plate springs open out of it in both
                // axes, and on the way out the plate shuts back to it, the card
                // hops a little further left as a wind-up, and only then leaves. Each stage waits on the
                // other spring's value, so the two overlap and the whole reads
                // as one gesture. The thresholds are the point; see
                // notes/notifications.md.
                readonly property bool closing: entry.closing

                // Deliberately far from shut: the hop has to start while the
                // plate is still visibly closing, or the exit reads as three
                // beats where the entry reads as one. A fifth from shut dwelt
                // long enough to be seen, and a third and a half were each
                // better but still left a flat spot; at 0.6 the whole hop lands
                // inside the plate's fastest closing, and the card leaves with
                // well over half the shut still to do in flight, shrinking
                // towards its icon as it goes.
                readonly property bool narrowed: card.opened <= 0.6

                // How far right of its resting place the card is parked: far
                // enough for the collapsed plate's left edge to clear the
                // surface, and no further. Off the plate's own x, which is half
                // the stack in on the way in — where counting the whole width
                // would spend most of the slide off screen — and pinned to
                // wherever the exit caught it on the way out.
                readonly property real travel: width + popupWindow.edgeGap - card.plateX

                // Where the plate shrinks onto while leaving: wherever it was
                // when the exit began. See NotificationCard.qml's `pinnedX`.
                property real closeX: 0

                // The wind-up starts when the plate is nearly shut — which, for
                // a toast dismissed before it ever opened, is already true by
                // the time `closing` arrives, so both edges are watched.
                // `start()` is latched, so whichever arrives second is a no-op.
                onClosingChanged: {
                    if (entryRoot.closing) {
                        entryRoot.closeX = card.plateX;
                        if (entryRoot.narrowed)
                            slide.start();
                    }
                }
                onNarrowedChanged: if (entryRoot.closing && entryRoot.narrowed)
                    slide.start()

                // Slides past the stack's right edge. A transform, not `x` —
                // the enclosing Column re-sets `x` on every relayout.
                transform: Translate {
                    x: slide.value
                }

                // The offset right of the resting place, in pixels: `travel` is
                // clear of the window, 0 is home. The same gesture the control
                // centre leaves by, with the arrival on the front of it —
                // `entryStiffness`/`entryDamping` are the defaults, tuned here.
                //
                // `landed` latches a sixth of the travel out, not at the
                // resting line: both stages move the icon leftwards, so
                // releasing the opening only once the slide had settled made
                // the icon run fast, stall, and run fast again. The OSD gets
                // this for free, its stages being perpendicular.
                //
                // The exit's last stage ends by destroying the delegate, which
                // runs inside the spring's own frame callback.
                DismissSlide {
                    id: slide
                    travel: entryRoot.travel
                    bump: NotificationTheme.popupBump
                    playEntry: true
                    entryLatchAt: entryRoot.travel * 0.15
                    onFinished: popupWindow.removeDisplayPopup(entryRoot.index, entryRoot.entry)
                }

                // The width the plate is open to; the card works the rest of
                // its rect out of it. Under damped on the way open (ζ ≈ 0.67)
                // — the overshoot and settle-back is the spring in the opening,
                // ~9px on each edge, and the gap the stack keeps from the
                // screen edge is the room the right one needs — and damped past
                // 1 on the way shut, where an undershoot would narrow the plate
                // past the icon it is a plate for.
                FrameSpring {
                    id: expand
                    to: slide.landed && !entryRoot.closing ? entryRoot.width : card.collapsedWidth
                    // The shut is the slower of the two, by request, and with
                    // it every spring the exit rides — see notes/notifications.md
                    // for the knob that stretches a spring without changing
                    // how it feels.
                    stiffness: slide.landed && !entryRoot.closing ? 122 : 92
                    damping: slide.landed && !entryRoot.closing ? 11.5 : 15.7
                }

                NotificationCard {
                    id: card
                    width: entryRoot.width
                    // The only thing driven from out here: the card works its
                    // whole rect, its content's offset and its reveal out of
                    // this one width, and snaps them to the output's pixel
                    // grid itself.
                    screen: popupWindow.screen
                    openWidth: expand.value
                    pinnedX: entryRoot.closing ? entryRoot.closeX : -1
                    wrapper: entryRoot.entry.display
                    floating: true
                    radius: NotificationTheme.popupRadius
                    // A closing toast is on its way out regardless.
                    interactive: !entryRoot.entry.closing
                }
            }
        }
    }
}
