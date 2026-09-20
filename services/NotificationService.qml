pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.shared

// The notification daemon: owns the DBus org.freedesktop.Notifications
// server and every list and timer the popup stack and control-center panel
// read. History is flat and newest-first, and `dnd` is in-memory only — it
// resets with the shell rather than persisting anywhere.
QtObject {
    id: root

    // ---- state ----

    // Flat history, newest first.
    property list<NotifWrapper> notifications: []
    // Visible toasts: a subset of notifications, plus transient ones.
    property list<NotifWrapper> popups: []

    // Control-center-only, grouped by app (key = desktop_entry ?? app_name).
    // One stable pass over a newest-first list puts each group at its newest
    // member's position, so a group rises as it gets new notifications with no
    // separate sort. Popups never group — they read `popups` directly.
    readonly property var notificationGroups: {
        const groups = [];
        const byKey = {};
        for (const w of root.notifications) {
            const key = w.groupKey;
            let g = byKey[key];
            if (!g) {
                g = {
                    "key": key,
                    "items": []
                };
                byKey[key] = g;
                groups.push(g);
            }
            g.items.push(w);
        }
        return groups;
    }

    // UI-only, not persisted. Here rather than on NotificationGroupCard so
    // the panel's keyboard handling can toggle a row without a delegate.
    property var expandedGroups: ({})

    function isGroupExpanded(key) {
        return !!root.expandedGroups[key];
    }

    function setGroupExpanded(key, state) {
        if (root.isGroupExpanded(key) === state)
            return;
        const copy = Object.assign({}, root.expandedGroups);
        if (state)
            copy[key] = true;
        else
            delete copy[key];
        root.expandedGroups = copy;
    }

    function toggleGroupExpanded(key) {
        root.setGroupExpanded(key, !root.isGroupExpanded(key));
    }

    property bool dnd: false
    property bool centerOpen: false
    // The ShellScreen whose indicator was last clicked (see toggleCenter);
    // shell.qml falls back to the main screen while null.
    property var centerScreen: null

    // Same, for the toast stack, captured from the focused monitor as each
    // notification arrives (see onNotification).
    property var popupScreen: null

    // Toast lifetimes in ms; critical's 0 means "no auto-dismiss".
    readonly property int timeoutLow: 5000
    readonly property int timeoutNormal: 10000
    readonly property int timeoutCritical: 0

    readonly property int count: notifications.length
    readonly property string iconState: dnd ? (count > 0 ? "dnd-notification" : "dnd-none") : (count > 0 ? "notification" : "none")

    // Re-clicking the screen the panel is on closes it; clicking a different
    // screen's indicator moves the panel there instead of closing it.
    function toggleCenter(screen) {
        if (root.centerOpen && root.centerScreen === screen) {
            root.centerOpen = false;
        } else {
            root.centerScreen = screen;
            root.centerOpen = true;
        }
    }

    function closeCenter() {
        root.centerOpen = false;
    }

    // Takes a toast off the stack, on timeout or because the panel opened. A
    // transient notification isn't in history, so nothing would reference it
    // after this — dismiss for real (Retainable below cleans up). A
    // non-transient one just leaves the stack.
    function releasePopup(wrapper) {
        wrapper.timer.stop();
        root.popups = root.popups.filter(w => w !== wrapper);
        if (root.notifications.indexOf(wrapper) === -1)
            root.dismiss(wrapper);
    }

    // No toasts while the panel is up: it already lists them, and the stack
    // would cover its top-right corner. Called from onCenterOpenChanged so
    // every path that opens the panel clears the stack.
    function clearPopups() {
        // Snapshot: releasePopup() reassigns `popups`.
        for (const w of root.popups.slice())
            root.releasePopup(w);
    }

    onCenterOpenChanged: {
        if (root.centerOpen)
            root.clearPopups();
    }

    function clearAll() {
        // Snapshot: dismiss() mutates `notifications` via onDropped.
        const toDismiss = root.notifications.slice();
        for (const w of toDismiss) {
            if (w.notification)
                w.notification.dismiss();
        }
        // Only the bulk path closes the panel, not one-by-one dismissal.
        root.centerOpen = false;
    }

    function dismiss(wrapper) {
        if (wrapper && wrapper.notification)
            wrapper.notification.dismiss();
    }

    // Dismisses whatever of these is still in history, on the next event-loop
    // pass. The control centre defers a dismissal until its exit gesture ends,
    // and that ends inside a spring's own frame callback — mutating the list
    // there regenerates every list delegate reentrantly, from under the spring
    // driving it. The liveness check is for the other half of that deferral: a
    // delegate destroyed mid-gesture still has to honour the click, and a
    // wrapper dropped in the meantime is a destroyed QObject that throws on
    // property access.
    function dismissLater(wrappers) {
        const pending = wrappers.slice();
        Qt.callLater(() => {
            for (const w of pending) {
                if (root.notifications.indexOf(w) !== -1)
                    root.dismiss(w);
            }
        });
    }

    // Snapshot as in clearAll(): dismiss() recomputes notificationGroups,
    // including this `group` object.
    function dismissGroup(group) {
        const toDismiss = group.items.slice();
        for (const w of toDismiss)
            root.dismiss(w);
    }

    // Apps whose notifications are status blips, not things to come back to:
    // shown as a toast, never kept in history.
    function isForcedTransient(appName) {
        return appName === "blueman" || appName === "NetworkManager Applet";
    }

    // A replacement (`replaces_id`, e.g. `notify-send -r` or a progress
    // notification) updates the Notification in place: the server emits no
    // `notification` for it, so this is what an update does that a plain
    // property binding can't — it is treated as an arrival. Its time is now,
    // its group rises, and it toasts again under the same rule as a new one,
    // with the timer restarted so a stream of updates keeps the toast up.
    function bump(wrapper) {
        wrapper.time = new Date();

        const at = root.notifications.indexOf(wrapper);
        if (at > 0)
            root.notifications = [wrapper, ...root.notifications.filter(w => w !== wrapper)];

        if (!root.dnd && !root.centerOpen) {
            root.popupScreen = Screens.focused();
            if (root.popups.indexOf(wrapper) === -1)
                root.popups = [...root.popups, wrapper];
            if (wrapper.timer.interval > 0)
                wrapper.timer.restart();
            else
                wrapper.timer.stop();
        }

        wrapper.updated();
    }

    // ---- notification wrapper ----

    component NotifWrapper: QtObject {
        id: wrapper

        required property Notification notification

        readonly property string summary: notification ? notification.summary : ""
        readonly property string body: notification ? notification.body : ""
        readonly property string appName: notification ? notification.appName : ""
        readonly property string appIcon: notification ? notification.appIcon : ""
        // What notificationGroups above keys on.
        readonly property string groupKey: notification ? (notification.desktopEntry || notification.appName) : ""
        readonly property string image: notification ? notification.image : ""
        readonly property int urgency: notification ? notification.urgency : NotificationUrgency.Normal
        // Reset by bump(): a replaced notification is as new as its update.
        property date time: new Date()
        readonly property string timeStr: Qt.formatTime(time, "HH:mm")

        // After bump() has applied a replacement — what the toast re-snapshots
        // on (NotificationPopupWindow.qml's PopupEntry).
        signal updated

        // One bump per replacement, not one per changed field: the server
        // sets every property in one update group, so the notifications land
        // together, and the pass they are coalesced into is also after the
        // group ends. The liveness check is for a wrapper dropped in between.
        property bool updatePending: false
        function noteUpdate() {
            if (wrapper.updatePending)
                return;
            wrapper.updatePending = true;
            Qt.callLater(() => {
                if (root.notifications.indexOf(wrapper) === -1 && root.popups.indexOf(wrapper) === -1)
                    return;
                wrapper.updatePending = false;
                root.bump(wrapper);
            });
        }

        // Set on one landing in an open panel, so the row built for it slides
        // in; cleared a pass later, so a rebuilt row starts at rest.
        property bool arriving: false

        readonly property list<NotificationAction> allActions: notification ? notification.actions : []
        // `?? null`: the property is typed, and undefined is not one.
        readonly property NotificationAction defaultAction: allActions.find(a => a.identifier === "default") ?? null
        readonly property list<NotificationAction> otherActions: allActions.filter(a => a.identifier !== "default")

        readonly property Timer timer: Timer {
            interval: {
                const appTimeout = wrapper.notification ? wrapper.notification.expireTimeout : -1;
                if (appTimeout >= 0)
                    return appTimeout;
                switch (wrapper.urgency) {
                case NotificationUrgency.Low:
                    return root.timeoutLow;
                case NotificationUrgency.Critical:
                    return root.timeoutCritical;
                default:
                    return root.timeoutNormal;
                }
            }
            running: false
            repeat: false
            onTriggered: root.releasePopup(wrapper)
        }

        readonly property Connections conn: Connections {
            target: wrapper.notification ? wrapper.notification.Retainable : null

            function onDropped() {
                root.notifications = root.notifications.filter(w => w !== wrapper);
                root.popups = root.popups.filter(w => w !== wrapper);
                wrapper.destroy();
            }

            function onAboutToDestroy() {
                wrapper.destroy();
            }
        }

        // Every field a replacement can change that is shown or timed. Each
        // only fires when its value differs, so a progress update that keeps
        // its summary still lands via body, hints or image.
        readonly property Connections updates: Connections {
            target: wrapper.notification

            function onSummaryChanged() {
                wrapper.noteUpdate();
            }
            function onBodyChanged() {
                wrapper.noteUpdate();
            }
            function onAppIconChanged() {
                wrapper.noteUpdate();
            }
            function onImageChanged() {
                wrapper.noteUpdate();
            }
            function onUrgencyChanged() {
                wrapper.noteUpdate();
            }
            function onActionsChanged() {
                wrapper.noteUpdate();
            }
            function onHintsChanged() {
                wrapper.noteUpdate();
            }
            function onExpireTimeoutChanged() {
                wrapper.noteUpdate();
            }
        }
    }

    property Component notifComponent: Component {
        NotifWrapper {}
    }

    property NotificationServer server: NotificationServer {
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: false
        inlineReplySupported: false
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            // `as NotifWrapper`: createObject() is statically QObject, so the
            // reads below are unverifiable without the cast.
            const wrapper = root.notifComponent.createObject(root, {
                "notification": notif
            }) as NotifWrapper;
            if (!wrapper)
                return;

            const transient = notif.transient || root.isForcedTransient(wrapper.appName);

            if (!transient) {
                wrapper.arriving = root.centerOpen;
                root.notifications = [wrapper, ...root.notifications];
                // The list rebuilds its rows inside that assignment, and
                // only those rows play the entry. Cleared a pass later, not by
                // the row: its spring reads the flag from its own
                // Component.onCompleted, after the row's. notes/notifications.md.
                if (wrapper.arriving)
                    Qt.callLater(() => {
                        if (root.notifications.indexOf(wrapper) !== -1)
                            wrapper.arriving = false;
                    });
            }

            // No toast while the panel is open — it's already in the list —
            // nor for one the server re-emits across a hot reload
            // (`keepOnReload`, the default): it was toasted the first time,
            // and it lands here with `centerOpen` false because the singleton
            // is fresh. History keeps it either way.
            if (!root.dnd && !root.centerOpen && !notif.lastGeneration) {
                root.popupScreen = Screens.focused();
                root.popups = [...root.popups, wrapper];
                if (wrapper.timer.interval > 0)
                    wrapper.timer.start();
            } else if (transient) {
                // Suppressed popup, no history, no timer to clean up: dismiss
                // now and let Retainable drop it.
                notif.dismiss();
            }
        }
    }
}
