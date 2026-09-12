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
    margins.top: Theme.barHeight + 10
    margins.right: 10

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Fully unmapped while empty, so no stray surface eats input. Tracks
    // displayPopupsModel, not NotificationService.popups, so the window
    // outlives the last card's exit spring.
    visible: displayPopupsModel.count > 0

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

    implicitWidth: Math.min(Math.max(maxNaturalWidth, NotificationTheme.popupMinWidth), NotificationTheme.popupMaxWidth)
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

                // Slides past the stack's right edge. A transform, not `x` —
                // the enclosing Column re-sets `x` on every relayout.
                transform: Translate {
                    x: offsetSpring.value
                }

                // Springs in on creation; on `entry.closing` it springs back
                // out, and the entry is dropped only once that settles.
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
                    // A closing toast is on its way out regardless.
                    interactive: !entryRoot.entry.closing
                }
            }
        }
    }
}
