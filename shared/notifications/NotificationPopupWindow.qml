pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Wayland
import qs.shared
import qs.services
import qs.shared.animations
import qs.shared.notifications

// Floating notification-toast stack in the top-right corner, just under the
// bar. Anchored to the screen corner and independent of any bar module, so
// this is a plain PanelWindow rather than the module-anchored PopupWindow
// machinery in ../popup/.
//
// One shared window, instantiated from shell.qml, whose `screen` follows
// NotificationService.popupScreen — the output focused when the notification
// arrived.
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

    // Fully unmapped while there's nothing to show: no footprint and no
    // stray input-eating surface. Tracks displayPopupsModel rather than
    // NotificationService.popups, so the window stays mapped through the last
    // card's exit spring instead of cutting it off.
    visible: displayPopupsModel.count > 0

    // Widest shown popup's naturalWidth (see NotificationCard.qml), clamped
    // to the min/max: most toasts sit at the minimum, while a long summary or
    // wide action labels push the stack out towards popupMaxWidth.
    readonly property real maxNaturalWidth: {
        let w = 0;
        for (let i = 0; i < popupRepeater.count; i++) {
            const item = popupRepeater.itemAt(i);
            if (item)
                w = Math.max(w, item.naturalWidth);
        }
        return w;
    }

    implicitWidth: Math.min(Math.max(maxNaturalWidth, NotificationTheme.popupMinWidth), NotificationTheme.popupMaxWidth)
    implicitHeight: column.implicitHeight

    // One entry per popup on screen: a superset of NotificationService.popups
    // that keeps a just-dismissed entry (closing: true) for the length of its
    // exit spring. Repeater destroys a delegate the instant its item leaves
    // the model with no way to animate that, so removal is deferred until the
    // card has finished sliding out (see removeDisplayPopup).
    //
    // `display` is a plain-value snapshot of `wrapper`'s fields, taken once on
    // creation, which NotificationCard binds to instead of `wrapper` itself.
    // Retaining the underlying Notification via Retainable.lock() was tried
    // first and still lost the race for one closed by the sending app's own
    // D-Bus CloseNotification call — that path apparently doesn't wait on the
    // retain count the way a local dismiss() does, and a burst of them
    // reliably logged a page of null-property errors. Reading `wrapper` once,
    // synchronously, while it's certainly live sidesteps the race rather than
    // trying to outrun it.
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
            // Not displayed: carried through so the card's click-to-dismiss
            // and close button still have a `.notification` to dismiss. Only
            // reachable while `interactive` is true, i.e. before `closing`.
            "notification": wrapper.notification
        }
    }

    // ListModel, not a `list<PopupEntry>` property reassigned by spread. That
    // was the original shape and it crashed Quickshell outright under a fast
    // burst of notifications: a whole-array reassignment makes Repeater tear
    // down and recreate *every* delegate on every add, and doing that
    // reentrantly — a second notification arriving while the first's delegate
    // is still incubating — segfaults inside QQuickRepeater::regenerate().
    // ListModel's append()/remove() are incremental, so Repeater only hears
    // about the row that changed.
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

    // `index` is the delegate's live Repeater index, kept up to date as rows
    // are added and removed — not one captured at creation.
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

                // Slides in from and out past the stack's right edge, which
                // sits flush against the screen's. A transform, not `x`: `x`
                // is owned by the enclosing Column, which re-sets it on every
                // relayout.
                transform: Translate {
                    x: offsetSpring.value
                }

                // Starts off-screen and springs to its resting position on
                // creation. Once `entry.closing` flips true it springs back
                // out, and only when that settles is the entry dropped.
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
                    // A closing toast is on its way out regardless of any
                    // click.
                    interactive: !entryRoot.entry.closing
                }
            }
        }
    }
}
