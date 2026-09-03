import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../../services"
import "../animations"

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
    // principle as Weather/Privacy/Tray's LazyLoaders. Tracks displayPopups,
    // not NotificationService.popups directly, so the window stays mapped
    // through the last card's exit spring instead of cutting it off.
    visible: displayPopups.length > 0

    implicitWidth: NotificationTheme.notificationWidth
    implicitHeight: column.implicitHeight

    // One entry per popup currently on screen — a superset of
    // NotificationService.popups that keeps a just-dismissed entry around
    // (closing: true) for the length of its exit spring. Repeater destroys
    // its delegate the instant an item leaves `model`, with no way to
    // animate that removal itself, so removal here is deferred until the
    // card has actually finished sliding out (see removeDisplayPopup).
    //
    // The entry's notification is Retainable-locked for as long as it lives
    // in this list. Without that, NotificationService.qml's dismiss-then-
    // destroy handlers (the Retainable `onDropped` Connections in its
    // NotifWrapper) can tear the wrapper down in the very same tick it
    // leaves `popups` — confirmed by reading that handler, which filters
    // `popups` and calls `wrapper.destroy()` together — which would leave a
    // still-animating card reading a destroyed object's properties.
    component PopupEntry: QtObject {
        required property var wrapper
        property bool closing: false
    }

    property list<PopupEntry> displayPopups: []

    property Component popupEntryComponent: Component {
        PopupEntry {}
    }

    function syncDisplayPopups() {
        const live = NotificationService.popups;

        for (const w of live) {
            if (displayPopups.some(e => e.wrapper === w))
                continue;
            w.notification.Retainable.lock();
            displayPopups = [...displayPopups, popupEntryComponent.createObject(popupWindow, {
                "wrapper": w
            })];
        }

        for (const e of displayPopups) {
            if (!e.closing && live.indexOf(e.wrapper) === -1)
                e.closing = true;
        }
    }

    function removeDisplayPopup(entry) {
        displayPopups = displayPopups.filter(e => e !== entry);
        if (entry.wrapper && entry.wrapper.notification)
            entry.wrapper.notification.Retainable.unlock();
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
            model: popupWindow.displayPopups

            Item {
                id: entryRoot
                required property var modelData
                readonly property var entry: modelData

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
                        snapTo(NotificationTheme.notificationWidth);
                        retarget(0);
                    }
                    onRunningChanged: if (!running && entryRoot.entry.closing)
                        popupWindow.removeDisplayPopup(entryRoot.entry)
                }

                Connections {
                    target: entryRoot.entry
                    function onClosingChanged() {
                        offsetSpring.retarget(NotificationTheme.notificationWidth);
                    }
                }

                NotificationCard {
                    id: card
                    width: entryRoot.width
                    wrapper: entryRoot.entry.wrapper
                    floating: true
                }
            }
        }
    }
}
