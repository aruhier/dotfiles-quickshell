pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Services.Notifications
import qs.shared

// The notification daemon: owns the DBus org.freedesktop.Notifications
// server and every list and timer the popup stack and control-center panel
// read. History is flat and newest-first. `dnd` survives a reload but not a
// restart: it persists nowhere outside the process.
//
// A `Singleton`, not a QtObject like the other services: only a Scope takes
// part in Quickshell's reload, and only its children are restored.
Singleton {
    id: root

    // ---- state ----

    // Flat history, newest first.
    property list<NotifWrapper> notifications: []
    // Visible toasts: a subset of notifications, plus transient ones.
    property list<NotifWrapper> popups: []

    // Control-center-only, grouped by app (key = desktop_entry ?? app_name),
    // newest group first. Popups never group — they read `popups` directly.
    // Two views of the same rows, kept in step below: `groupModel` for the
    // panel's ListView, incremental so a change touches one row's delegate
    // rather than rebuilding all (notes/notifications.md); `notificationGroups`
    // for indexed access, since `groupModel.get(i)` sets up no binding.
    readonly property ListModel groupModel: ListModel {}
    property list<NotifGroup> notificationGroups: []
    // Every group ever made, by key. Never destroyed: a released row can
    // outlive its removal, and a dead group under it crashed the engine.
    property var groupsByKey: ({})

    function groupFor(key) {
        let group = root.groupsByKey[key];
        if (!group) {
            group = root.groupComponent.createObject(root, {
                "key": key
            }) as NotifGroup;
            root.groupsByKey[key] = group;
        }
        return group;
    }

    function groupIndex(group) {
        return root.notificationGroups.indexOf(group);
    }

    function moveGroupToFront(group) {
        const at = root.groupIndex(group);
        if (at <= 0)
            return;
        root.groupModel.move(at, 0, 1);
        root.notificationGroups = [group, ...root.notificationGroups.filter(g => g !== group)];
    }

    // Newest first in history and in its group; the group rises to the top.
    function insertWrapper(wrapper) {
        root.notifications = [wrapper, ...root.notifications];

        const group = root.groupFor(wrapper.groupKey);
        const listed = group.items.length > 0;
        wrapper.group = group;
        group.items = [wrapper, ...group.items];
        if (listed) {
            root.moveGroupToFront(group);
            return;
        }
        root.groupModel.insert(0, {
            "group": group
        });
        root.notificationGroups = [group, ...root.notificationGroups];
    }

    // A group left empty goes too. Row order is otherwise kept: a group
    // doesn't drop because its newest member was dismissed.
    function removeWrapper(wrapper) {
        root.notifications = root.notifications.filter(w => w !== wrapper);

        const group = wrapper.group;
        if (!group)
            return;
        group.items = group.items.filter(w => w !== wrapper);
        if (group.items.length > 0)
            return;
        root.groupModel.remove(root.groupIndex(group));
        root.notificationGroups = root.notificationGroups.filter(g => g !== group);
    }

    // What a replacement does to a listed notification. Every step is a
    // no-op when already at the front, so a stream of updates rebuilds nothing.
    function raiseWrapper(wrapper) {
        if (root.notifications.indexOf(wrapper) > 0)
            root.notifications = [wrapper, ...root.notifications.filter(w => w !== wrapper)];
        const group = wrapper.group;
        if (!group)
            return;
        if (group.items.indexOf(wrapper) > 0)
            group.items = [wrapper, ...group.items.filter(w => w !== wrapper)];
        root.moveGroupToFront(group);
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

    // Kept across a Quickshell reload, which rebuilds this singleton: every
    // config edit used to turn Do Not Disturb off. Restored just after
    // creation, by `reloaded`; the alias carries the change to readers.
    property alias dnd: persisted.dnd
    PersistentProperties {
        id: persisted
        reloadableId: "notificationService"
        property bool dnd: false
    }
    property bool centerOpen: false
    // The ShellScreen whose indicator was last clicked (see toggleCenter);
    // shell.qml falls back to the main screen while null.
    property var centerScreen: null

    // Same, for the toast stack: the focused monitor for a new notification,
    // kept for a replacement unless nothing is shown (see bump).
    property var popupScreen: null
    // Written by the toast window: anything still drawn, a toast sliding
    // out included, which `popups` no longer lists.
    property bool toastsShown: false

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

    // Takes a toast off the stack, on timeout, because the panel opened, or
    // after a resident one's action. A transient notification isn't in
    // history, so nothing would reference it after this — close it for real
    // (Retainable below cleans up), as expired if its timer ran out. A
    // non-transient one just leaves the stack.
    function releasePopup(wrapper, expired) {
        wrapper.timer.stop();
        wrapper.held = false;
        root.popups = root.popups.filter(w => w !== wrapper);
        if (root.notifications.indexOf(wrapper) !== -1 || !wrapper.notification)
            return;
        if (expired)
            wrapper.notification.expire();
        else
            wrapper.notification.dismiss();
    }

    // Stops a toast's timeout while the cursor is on it; leaving restarts it
    // in full, so a toast just read isn't gone the moment it's let go.
    function holdPopup(wrapper, held) {
        if (!root.isLive(wrapper) || root.popups.indexOf(wrapper) === -1)
            return;
        wrapper.held = held;
        if (held)
            wrapper.timer.stop();
        else
            root.armTimer(wrapper);
    }

    // (Re)starts a toast's timeout, unless the cursor is holding it: a
    // replacement landing on a hovered toast mustn't expire it under it.
    function armTimer(wrapper) {
        if (wrapper.held)
            return;
        if (wrapper.timer.interval > 0)
            wrapper.timer.restart();
        else
            wrapper.timer.stop();
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
        if (root.centerOpen) {
            root.clearPopups();
        } else {
            // An arrival no row played (landed out of view, no delegate) is
            // dropped on close, so the next open shows every row at rest.
            for (const w of root.notifications)
                w.arriving = false;
        }
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
                if (root.isLive(w))
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

    // Whether a wrapper is still listed, in history or on the toast stack. A
    // dropped one is a dead QObject — not null, and even `indexOf` throws on
    // it — so this is the one place that asks, and it answers false rather
    // than throwing.
    function isLive(wrapper) {
        try {
            return root.notifications.indexOf(wrapper) !== -1 || root.popups.indexOf(wrapper) !== -1;
        } catch (e) {
            return false;
        }
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
        root.raiseWrapper(wrapper);

        if (!root.dnd && (!root.centerOpen || wrapper.isTransient)) {
            // The stack stays put, or a progress stream would drag every
            // toast between outputs — unless nothing is shown, or its output
            // was unplugged (a deleted screen notifies nobody).
            if (!root.toastsShown || Quickshell.screens.indexOf(root.popupScreen) === -1)
                root.popupScreen = Screens.focused();
            root.showPopup(wrapper);
        }

        wrapper.updated();
    }

    // Puts a toast up, or keeps it up with its timer restarted. Where the
    // stack is, the caller decides.
    function showPopup(wrapper) {
        if (root.popups.indexOf(wrapper) === -1)
            root.popups = [...root.popups, wrapper];
        root.armTimer(wrapper);
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
        // Never kept in history, so only ever a toast: the app's `transient`
        // hint or isForcedTransient() (set on arrival; see onNotification).
        // Not `transient`, which QML reserves.
        property bool isTransient: false
        // Under the cursor: its timeout is stopped (see holdPopup).
        property bool held: false
        readonly property bool resident: notification ? notification.resident : false
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
                if (!root.isLive(wrapper))
                    return;
                wrapper.updatePending = false;
                root.bump(wrapper);
            });
        }

        // Its NotifGroup, from insertWrapper(). `var`: NotifGroup is declared
        // after this component and holds a list of these.
        property var group: null

        // Set on landing in an open panel; cleared by the row that plays the
        // arrival, not a pass later — ListView builds a new delegate at its
        // next polish, after a Qt.callLater would have fired (verified).
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
            onTriggered: root.releasePopup(wrapper, true)
        }

        readonly property Connections conn: Connections {
            target: wrapper.notification ? wrapper.notification.Retainable : null

            function onDropped() {
                root.removeWrapper(wrapper);
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

    // One panel row: an app's notifications, newest first. An object, so a
    // delegate keeps it across changes to `items`.
    component NotifGroup: QtObject {
        required property string key
        property list<NotifWrapper> items: []
    }

    property Component groupComponent: Component {
        NotifGroup {}
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
            wrapper.isTransient = transient;

            if (!transient) {
                wrapper.arriving = root.centerOpen;
                root.insertWrapper(wrapper);
            }

            // No toast while the panel is open — it's already in the list —
            // unless it's transient, which the list never shows. Nor for one
            // the server re-emits across a hot reload (`keepOnReload`, the
            // default): it was toasted the first time, and it lands here with
            // `centerOpen` false because the singleton is fresh.
            if (!root.dnd && (!root.centerOpen || transient) && !notif.lastGeneration) {
                // A new one goes where the user is looking.
                root.popupScreen = Screens.focused();
                root.showPopup(wrapper);
            } else if (transient) {
                // Suppressed popup, no history, no timer to clean up: dismiss
                // now and let Retainable drop it.
                notif.dismiss();
            }
        }
    }
}
