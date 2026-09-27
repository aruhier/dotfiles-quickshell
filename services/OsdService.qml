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
    // "numlock", "scrolllock" or "message".
    property string kind: ""
    property var screen: null

    // What a "message" shows; lock-key styled, `on` lighting the glyph.
    property string messageGlyph: ""
    property string messageText: ""
    property bool messageOn: false

    // `screen` is optional. Every other trigger is a keybind, which has no
    // widget to report a screen, so the OSD lands on the focused output.
    // Keeping the last one is what makes the hide animation finish on the
    // screen it started on.
    function show(kind, screen) {
        root.screen = screen || Screens.focused() || root.screen;
        root.kind = kind;
        hideTimer.restart();
    }

    function showMessage(glyph, text, on, screen) {
        root.messageGlyph = glyph;
        root.messageText = text;
        root.messageOn = on;
        root.show("message", screen);
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
