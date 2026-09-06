pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Wayland
import qs.shared
import qs.services
import qs.shared.animations
import qs.shared.notifications

// Floating notification-toast stack, top-right corner, sitting just under
// the bar and its border stripe (barHeight + barBorderHeight), plus the
// same 10px gap used on the right edge. Screen-corner-anchored and
// independent of any bar module though,
// so a plain PanelWindow (same base Bar.qml itself uses) is the right fit
// here, not the module-anchored PopupWindow machinery in ../popup/ (that's
// built specifically to anchor below a *specific* bar module).
//
// Instantiated once from shell.qml — a single, shared window (not one per
// output), whose `screen` follows NotificationService.popupScreen: the
// output Hyprland had focused at the moment the notification arrived (set
// in NotificationService.qml's onNotification), falling back to the main
// screen before the first-ever notification. Same "single surface that
// follows the relevant output" shape as NotificationCenterPanel.qml's
// centerScreen, just captured at notification-arrival time instead of
// indicator-click time since a toast has no click of its own to anchor to.
PanelWindow {
    id: popupWindow

    anchors {
        top: true
        right: true
    }
    margins.top: Theme.barHeight + 10
    margins.right: 10

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Fully unmapped (zero footprint, no stray input-eating surface) while
    // there's nothing to show — same "don't pay for what isn't shown"
    // principle as Weather/Privacy/Tray's LazyLoaders. Tracks
    // displayPopupsModel, not NotificationService.popups directly, so the
    // window stays mapped through the last card's exit spring instead of
    // cutting it off.
    visible: displayPopupsModel.count > 0

    // Widest currently-shown popup's naturalWidth (see NotificationCard.qml),
    // clamped to [notificationMinWidth, notificationMaxWidth] — most toasts
    // are short and sit at the minimum; a long summary or wide action labels
    // push the whole stack wider, up to a control-center card's width.
    readonly property real maxNaturalWidth: {
        let w = 0;
        for (let i = 0; i < popupRepeater.count; i++) {
            const item = popupRepeater.itemAt(i);
            if (item)
                w = Math.max(w, item.naturalWidth);
        }
        return w;
    }

    implicitWidth: Math.min(Math.max(maxNaturalWidth, NotificationTheme.notificationMinWidth), NotificationTheme.notificationMaxWidth)
    implicitHeight: column.implicitHeight

    // One entry per popup currently on screen — a superset of
    // NotificationService.popups that keeps a just-dismissed entry around
    // (closing: true) for the length of its exit spring. Repeater destroys
    // its delegate the instant an item leaves `model`, with no way to
    // animate that removal itself, so removal here is deferred until the
    // card has actually finished sliding out (see removeDisplayPopup).
    //
    // `display` is a plain-value snapshot of `wrapper`'s fields taken once,
    // immediately on creation — NotificationCard is bound to it instead of
    // to `wrapper` directly. First attempt at this used Retainable.lock()
    // to keep `wrapper`'s underlying Notification alive for the entry's
    // whole life, reacting to aboutToDestroy to cut the animation short if
    // that failed anyway — and it still lost the race for a notification
    // closed via the sending app's own D-Bus CloseNotification call
    // (confirmed empirically: a burst of Notify-then-CloseNotification
    // calls reliably logged a page of "Cannot read property of null" from
    // NotificationCard, the lock/aboutToDestroy handling notwithstanding —
    // apparently that path doesn't wait on the retain count the way a
    // locally-initiated dismiss() does). Reading `wrapper` exactly once,
    // synchronously, at the point it's certainly live (it was just added to
    // NotificationService.popups this same tick) sidesteps that race
    // instead of trying to outrun it.
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
            // Not read for display — carried through so
            // NotificationService.dismiss(card.wrapper) (click-to-dismiss
            // and the close button, both in NotificationCard.qml) still
            // has a `.notification` to call dismiss() on. Only reachable
            // while `interactive` is true, i.e. before `closing`, so this
            // is never invoked once the underlying object's lifetime is
            // out of this window's hands anyway.
            "notification": wrapper.notification
        }
    }

    // ListModel, not a plain `list<PopupEntry>` property reassigned via
    // spread (`displayPopups = [...displayPopups, x]`) — that was the
    // original shape here and it crashed Quickshell outright under a fast
    // burst of notifications (confirmed via a coredump: the crash's own
    // stacktrace was a segfault inside QQuickRepeater::regenerate(),
    // reached from QQuickRepeater::setModel() while a *previous*
    // regenerate's QQmlObjectCreator::finalize() for a still-incubating
    // delegate was still on the stack). A whole-array reassignment makes
    // Repeater tear down and recreate *every* delegate on every single
    // add, and doing that reentrantly — a second notification arriving
    // while the first's delegate is still being incubated — hit a real Qt
    // crash, not just a QML-level bug. ListModel's append()/remove() are
    // incremental (Repeater is only told about the one row that changed),
    // which is the standard, reentrancy-safe idiom for a dynamically
    // growing/shrinking animated list and doesn't hit this at all.
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

    // `index` is the delegate's own live Repeater index (kept up to date
    // as other rows are added/removed), not one captured at creation —
    // safe to use here even though other entries may have been removed
    // since this one was created.
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
        width: parent.width
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

                // Slides in from, and out to, past the stack's own right
                // edge — which already sits flush against the screen's
                // right edge (see popupWindow's margins.right) — replacing
                // the plain opacity fade this used to do. A transform, not
                // `x`, since `x` is owned by the enclosing Column
                // (positioners re-set it on every relayout).
                transform: Translate {
                    x: offsetSpring.value
                }

                // FrameSpring, not Behavior/SpringAnimation — see
                // FrameSpring.qml's header comment and AGENT.md's "capped
                // near 60Hz" section for why a frame-driven spring is used
                // instead everywhere else in this repo. Starts already
                // off-screen and springs to resting position on creation;
                // once `entry.closing` flips true it springs back out, and
                // only once *that* settles (running goes false again) is
                // the entry actually dropped from displayPopups.
                FrameSpring {
                    id: offsetSpring
                    Component.onCompleted: {
                        snapTo(popupWindow.width);
                        retarget(0);
                    }
                    onRunningChanged: if (!running && entryRoot.entry.closing)
                        popupWindow.removeDisplayPopup(entryRoot.index, entryRoot.entry)
                }

                Connections {
                    target: entryRoot.entry
                    function onClosingChanged() {
                        offsetSpring.retarget(popupWindow.width);
                    }
                }

                NotificationCard {
                    id: card
                    width: entryRoot.width
                    wrapper: entryRoot.entry.display
                    floating: true
                    // Closing toasts are on their way out regardless of
                    // click — matches NotificationGroupCard.qml's peeking
                    // (non-front) layers, which disable interaction for the
                    // same "this isn't really the thing to click" reason.
                    interactive: !entryRoot.entry.closing
                }
            }
        }
    }
}
