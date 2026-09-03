pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "../shared/notifications"

// Native notification daemon + state, replacing swaync. Owns the DBus
// org.freedesktop.Notifications server and every list/timer driving the
// popup stack (NotificationPopupWindow.qml) and control-center panel
// (NotificationCenterPanel.qml) — both just read this singleton, per this
// repo's usual services-own-I/O-and-state split.
//
// Deliberately simpler than swaync itself in a few places:
// - flat history, newest first — no per-app grouping/dedup (swaync doesn't
//   group by default either).
// - `dnd` is in-memory only, not GSettings/dconf-backed like swaync's —
//   depending on swaync's own schema surviving would be a fragile link for
//   a system meant to replace it outright.
QtObject {
    id: root

    // ---- state ----

    // Flat history, newest first.
    property list<NotifWrapper> notifications: []
    // Currently-visible floating toasts (subset of notifications, plus
    // transient ones that never join history).
    property list<NotifWrapper> popups: []

    // Control-center-only view of `notifications`, grouped by app the same
    // way swaync does (notiModel.vala: name_id = desktop_entry ?? app_name)
    // — see notificationGroup.vala/expandableGroup.vala vendored under
    // ~/git/github/SwayNotificationCenter for the reference implementation
    // NotificationGroupCard.qml mirrors. A group's position follows its
    // newest member: `notifications` is already newest-first, and this does
    // one stable pass over it, so a group is created at (and stays at) the
    // position of the first — i.e. newest — notification seen for that key,
    // with every older notification for the same app folding into it right
    // there. That reproduces swaync's "group re-sorts to its latest
    // notification's time" behavior without needing a separate sort step.
    // Floating popups never group like this (notificationWindow.vala just
    // appends each notification to a flat list) — NotificationPopupWindow.qml
    // deliberately keeps reading `popups` directly.
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

    // Which grouped rows are expanded in the control center — keyed by
    // group key, same shape/rationale as `dnd` (UI-only, not persisted).
    // Lives here rather than as local state on NotificationGroupCard so
    // NotificationCenterPanel.qml's keyboard handling (Return to
    // expand/collapse the selected row) can drive it without reaching into
    // a specific delegate instance.
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
    // Which output the panel should appear on — the screen whose bar
    // indicator was last clicked, not always the same output (see
    // toggleCenter below). NotificationCenterPanel.qml (via shell.qml)
    // reads this to pick its `screen`, falling back to the main screen
    // while null (e.g. before the first-ever click). Holds an actual
    // ShellScreen, not a name — same shape DankMaterialShell's
    // PopoutManager uses for its per-output popouts (`triggerScreen`),
    // compared for this fix.
    property var centerScreen: null

    // Which output the toast stack should appear on — captured fresh for
    // each incoming notification (see onNotification below) from whichever
    // monitor Hyprland currently has focused, same "capture at trigger
    // time" shape as centerScreen above (there it's the clicked indicator's
    // screen; here there's no click to anchor to, so focused-at-arrival is
    // the nearest equivalent). NotificationPopupWindow.qml (via shell.qml)
    // reads this, falling back to the main screen while null (before the
    // first-ever notification, or if Hyprland reports an unknown monitor).
    property var popupScreen: null

    function screenByName(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return null;
    }

    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        return (monitor && root.screenByName(monitor.name)) || null;
    }

    readonly property int count: notifications.length
    readonly property string iconState: dnd ? (count > 0 ? "dnd-notification" : "dnd-none") : (count > 0 ? "notification" : "none")

    // screen: the output whose bar indicator was clicked (each per-output
    // NotificationCenter.qml passes its own `Bar.screen`). Clicking the
    // indicator on the screen the panel is already open on toggles it
    // closed, same as before; clicking a *different* screen's indicator
    // instead moves the (still-single, shared) panel there and keeps it
    // open — mirrors how most multi-monitor panels behave rather than just
    // closing a panel the user is actively pointing at.
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

    function clearAll() {
        // Snapshot first: dismiss() below mutates `notifications` via the
        // Retainable onDropped handler as we go.
        const toDismiss = root.notifications.slice();
        for (const w of toDismiss) {
            if (w.notification)
                w.notification.dismiss();
        }
        // swaync's hide-on-clear: only the bulk clear-all path auto-closes
        // the panel, not one-by-one dismissal.
        root.centerOpen = false;
    }

    function dismiss(wrapper) {
        if (wrapper && wrapper.notification)
            wrapper.notification.dismiss();
    }

    // Group close-all — swaync's NotificationGroup.request_dismiss_all_notifications.
    // Snapshot first for the same reason clearAll() does: dismiss() mutates
    // `notifications` (and thus recomputes notificationGroups, including
    // this same `group` object) as we go.
    function dismissGroup(group) {
        const toDismiss = group.items.slice();
        for (const w of toDismiss)
            root.dismiss(w);
    }

    // config.json's notification-visibility overrides forcing these two
    // apps' notifications to be treated as transient (popup-only, never
    // kept in history).
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
        // swaync's notiModel.vala: name_id = desktop_entry ?? app_name — the
        // key notificationGroups (above) groups control-center rows by.
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
                // Transient notifications aren't kept in history — once
                // their popup times out there's nothing left referencing
                // them, so dismiss for real (drives cleanup via Retainable
                // below). Non-transient ones just leave the popup stack and
                // stay in history until the user dismisses/clears them.
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

            const wrapper = root.notifComponent.createObject(root, {
                "notification": notif
            });
            if (!wrapper)
                return;

            const transient = notif.transient || root.isForcedTransient(wrapper.appName);

            if (!transient)
                root.notifications = [wrapper, ...root.notifications];

            if (!root.dnd) {
                root.popupScreen = root.focusedScreen();
                root.popups = [...root.popups, wrapper];
                if (wrapper.timer.interval > 0)
                    wrapper.timer.start();
            }
        }
    }
}
