pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland

// Every Hyprland.refresh* call goes through here. Quickshell drops a refresh
// asked for while one of the same kind is in flight, and nothing reports when
// one lands, so callers asking independently could lose each other's. Asks are
// coalesced, and every refresh is sent twice: the second fetches whatever the
// first raced with. See notes/autohide.md.
QtObject {
    id: root

    function toplevels() {
        root.pendingToplevels = true;
        lead.start();
    }

    function monitors() {
        root.pendingMonitors = true;
        lead.start();
    }

    property bool pendingToplevels: false
    property bool pendingMonitors: false
    property bool trailToplevels: false
    property bool trailMonitors: false

    function send(toplevels, monitors) {
        if (toplevels)
            Hyprland.refreshToplevels();
        if (monitors)
            Hyprland.refreshMonitors();
    }

    property Timer lead: Timer {
        id: lead
        // Two windows opening together land in one refresh.
        interval: 50
        onTriggered: {
            root.send(root.pendingToplevels, root.pendingMonitors);
            root.trailToplevels = root.trailToplevels || root.pendingToplevels;
            root.trailMonitors = root.trailMonitors || root.pendingMonitors;
            root.pendingToplevels = false;
            root.pendingMonitors = false;
            trail.restart();
        }
    }

    property Timer trail: Timer {
        id: trail
        // Well past a socket round trip, so the first refresh has landed.
        interval: 150
        onTriggered: {
            root.send(root.trailToplevels, root.trailMonitors);
            root.trailToplevels = false;
            root.trailMonitors = false;
        }
    }
}
