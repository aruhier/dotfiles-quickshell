pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Ensures only one hover popup (Clock's calendar, Weather's forecast, …) is
// open at a time process-wide. Without this, moving the cursor directly
// from one module to an adjacent one leaves both popups open during the
// 200ms close grace period, and their surfaces visually overlap. There's
// only ever one cursor, so a single global owner is enough — no need to
// scope this per output.
QtObject {
    id: root

    property var activeOwner: null

    // owner: the requesting HoverPopup instance, exposing close().
    function activate(owner) {
        if (activeOwner && activeOwner !== owner)
            activeOwner.close();
        activeOwner = owner;
    }

    function deactivate(owner) {
        if (activeOwner === owner)
            activeOwner = null;
    }
}
