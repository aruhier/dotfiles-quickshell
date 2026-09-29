pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// The hover policy shared by every popup and tooltip. Keeps only one hover
// popup open at a time: moving the cursor straight to a neighbouring module
// otherwise leaves both up, overlapping, for the close grace period. One
// cursor, so one global owner is enough.
QtObject {
    id: root

    // Dwell before a popup or tooltip opens, so a cursor crossing the bar
    // neither flashes them open nor pays to build them.
    readonly property int hoverDwell: 500

    property var activeOwner: null
    // The tray icon whose menu is open, or null. Not an owner — menus close
    // themselves — but the bar holds a peek open for one, as it does for
    // activeOwner.
    property var trayMenuOwner: null

    // owner: the requesting HoverPopup, which exposes close().
    function activate(owner) {
        if (root.activeOwner && root.activeOwner !== owner)
            root.activeOwner.close();
        root.activeOwner = owner;
    }

    function deactivate(owner) {
        if (root.activeOwner === owner)
            root.activeOwner = null;
    }
}
