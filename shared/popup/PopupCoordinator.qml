pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Keeps only one hover popup open at a time: moving the cursor straight to a
// neighbouring module otherwise leaves both up, overlapping, for the close
// grace period. One cursor, so one global owner is enough.
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
