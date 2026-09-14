pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// What the on-screen display is showing, and on which output. One shared
// window follows this (see shared/osd/OsdWindow.qml), the same way the
// notification centre follows NotificationService.centerScreen.
QtObject {
    id: root

    // "" while hidden; otherwise "volume", "brightness", "capslock",
    // "numlock" or "scrolllock".
    property string kind: ""
    property var screen: null

    function show(kind) {
        // Every trigger is a keybind, which has no widget to report a screen,
        // so the OSD lands on the focused output. Keeping the last one is what
        // makes the hide animation finish on the screen it started on.
        root.screen = Screens.focused() || root.screen;
        root.kind = kind;
        hideTimer.restart();
    }

    function hide() {
        hideTimer.stop();
        root.kind = "";
    }

    property Timer hideTimer: Timer {
        // Held long enough that the rise and the drop are a small part of
        // what is on screen: a second leaves the pill on its way out about as
        // soon as the eye has found it.
        interval: 2500
        onTriggered: root.kind = ""
    }
}
