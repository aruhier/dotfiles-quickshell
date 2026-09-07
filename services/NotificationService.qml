pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.shared
import qs.shared.notifications

// Native notification daemon and state, replacing swaync. Owns the DBus
// org.freedesktop.Notifications server and every list and timer driving the
// popup stack and control-center panel, which both just read this singleton.
//
// Deliberately simpler than swaync in two places: history is flat and
// newest-first, and `dnd` is in-memory only rather than GSettings-backed —
// depending on swaync's own schema surviving would be a fragile link for a
// system meant to replace it.
QtObject {
    id: root

    // ---- state ----

    // Flat history, newest first.
    property list<NotifWrapper> notifications: []
    // Currently-visible floating toasts (subset of notifications, plus
    // transient ones that never join history).
    property list<NotifWrapper> popups: []

    // Control-center-only view of `notifications`, grouped by app the way
    // swaync does (key = desktop_entry ?? app_name). One stable pass over an
    // already newest-first list, so a group is created at — and stays at —
    // the position of its newest member, with older ones for the same app
    // folding in there. That reproduces swaync's "group re-sorts to its latest
    // notification's time" without a separate sort step.
    //
    // Floating popups never group like this; NotificationPopupWindow.qml
    // reads `popups` directly.
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

    // Which grouped rows are expanded in the control center. UI-only and not
    // persisted, like `dnd`. Lives here rather than on NotificationGroupCard
    // so the panel's keyboard handling can toggle the selected row without
    // reaching into a specific delegate.
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
    // Which output the panel appears on: the screen whose bar indicator was
    // last clicked (see toggleCenter). An actual ShellScreen, not a name.
    // shell.qml reads it, falling back to the main screen while null.
    property var centerScreen: null

    // Which output the toast stack appears on, captured from the focused
    // monitor as each notification arrives (see onNotification). Same
    // capture-at-trigger-time shape as centerScreen, except a toast has no
    // click to anchor to. shell.qml falls back to the main screen while null.
    property var popupScreen: null

    readonly property int count: notifications.length
    readonly property string iconState: dnd ? (count > 0 ? "dnd-notification" : "dnd-none") : (count > 0 ? "notification" : "none")

    // screen: the output whose bar indicator was clicked. Clicking the
    // indicator on the screen the panel is already open on closes it; clicking
    // a *different* screen's indicator moves the shared panel there and keeps
    // it open, rather than closing a panel the user is pointing at.
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

    // swaync hides its toast stack while the control center is up: the panel
    // already lists every notification a toast would show, and the stack
    // shares the panel's top-right corner so it covers the first card too.
    // Called from onCenterOpenChanged rather than toggleCenter(), so every
    // path that opens the panel clears the stack.
    function clearPopups() {
        const toClear = root.popups.slice();
        root.popups = [];
        for (const w of toClear) {
            w.timer.stop();
            // Same cleanup the popup timer's onTriggered does: a transient
            // notification never enters `notifications`, so once its popup is
            // gone nothing references it and it must be dismissed for real.
            if (root.notifications.indexOf(w) === -1 && w.notification)
                w.notification.dismiss();
        }
    }

    onCenterOpenChanged: {
        if (root.centerOpen)
            root.clearPopups();
    }

    function clearAll() {
        // Snapshot first: dismiss() mutates `notifications` via the Retainable
        // onDropped handler as we go.
        const toDismiss = root.notifications.slice();
        for (const w of toDismiss) {
            if (w.notification)
                w.notification.dismiss();
        }
        // swaync's hide-on-clear: only the bulk path auto-closes the panel,
        // not one-by-one dismissal.
        root.centerOpen = false;
    }

    function dismiss(wrapper) {
        if (wrapper && wrapper.notification)
            wrapper.notification.dismiss();
    }

    // Snapshot first for the same reason clearAll() does: dismiss() mutates
    // `notifications`, which recomputes notificationGroups — including this
    // same `group` object.
    function dismissGroup(group) {
        const toDismiss = group.items.slice();
        for (const w of toDismiss)
            root.dismiss(w);
    }

    // swaync's notification-visibility overrides: these two apps are treated
    // as transient, i.e. popup-only and never kept in history.
    function isForcedTransient(appName) {
        return appName === "blueman" || appName === "NetworkManager Applet";
    }

    // ---- notification wrapper ----

    component NotifWrapper: QtObject {
        id: wrapper

        required property Notification notification

        readonly property string summary: notification ? notification.summary : ""
        readonly property string body: notification ? notification.body : ""
        readonly property string appName: notification ? notification.appName : ""
        readonly property string appIcon: notification ? notification.appIcon : ""
        // The key notificationGroups above groups control-center rows by.
        readonly property string groupKey: notification ? (notification.desktopEntry || notification.appName) : ""
        readonly property string image: notification ? notification.image : ""
        readonly property int urgency: notification ? notification.urgency : NotificationUrgency.Normal
        readonly property date time: new Date()
        readonly property string timeStr: Qt.formatTime(time, "HH:mm")

        readonly property list<NotificationAction> allActions: notification ? notification.actions : []
        readonly property NotificationAction defaultAction: {
            for (const a of allActions) {
                if (a.identifier === "default")
                    return a;
            }
            return null;
        }
        readonly property list<NotificationAction> otherActions: allActions.filter(a => a.identifier !== "default")

        readonly property Timer timer: Timer {
            interval: {
                const appTimeout = wrapper.notification ? wrapper.notification.expireTimeout : -1;
                if (appTimeout >= 0)
                    return appTimeout;
                switch (wrapper.urgency) {
                case NotificationUrgency.Low:
                    return NotificationTheme.timeoutLow;
                case NotificationUrgency.Critical:
                    return NotificationTheme.timeoutCritical;
                default:
                    return NotificationTheme.timeoutNormal;
                }
            }
            running: false
            repeat: false
            onTriggered: {
                root.popups = root.popups.filter(w => w !== wrapper);
                // Transient notifications aren't kept in history, so once
                // their popup times out nothing references them and they must
                // be dismissed for real (cleanup runs via Retainable below).
                // Non-transient ones just leave the stack.
                if (root.notifications.indexOf(wrapper) === -1 && wrapper.notification)
                    wrapper.notification.dismiss();
            }
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

            // `as NotifWrapper`: createObject() is statically typed QObject,
            // so every wrapper.<field> read below is unverifiable without the
            // cast.
            const wrapper = root.notifComponent.createObject(root, {
                "notification": notif
            }) as NotifWrapper;
            if (!wrapper)
                return;

            const transient = notif.transient || root.isForcedTransient(wrapper.appName);

            if (!transient)
                root.notifications = [wrapper, ...root.notifications];

            // No toast while the panel is open, for the same reason
            // clearPopups() empties the stack: the notification is already
            // visible in the list this just prepended it to.
            if (!root.dnd && !root.centerOpen) {
                root.popupScreen = Screens.focused();
                root.popups = [...root.popups, wrapper];
                if (wrapper.timer.interval > 0)
                    wrapper.timer.start();
            } else if (transient) {
                // Suppressed popup and not in history: nothing holds this
                // one and no popup timer will fire to clean it up, so dismiss
                // now and let Retainable drop it.
                notif.dismiss();
            }
        }
    }
}
