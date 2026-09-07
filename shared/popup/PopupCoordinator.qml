pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Keeps only one hover popup (Clock's calendar, Weather's forecast, …) open at
// a time. Without it, moving the cursor straight from one module to its
// neighbour leaves both open for the 200ms close grace period and their
// surfaces overlap. One cursor, so one global owner is enough — no need to
// scope this per output.
QtObject {
    id: root

    property var activeOwner: null

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
