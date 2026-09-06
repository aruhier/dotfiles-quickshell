pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// Every piece of text in this shell. Exists so the three things that are the
// same at all ~65 text sites stop being a convention someone has to remember:
//
//  - `renderType: Text.NativeRendering`. The default SDF renderer shows
//    visible chromatic fringing on this machine, and there is no global
//    setting for it — before this type, every single `Text {}` had to opt in
//    by hand, and a missed one is a subtle rendering regression nobody would
//    file a bug about.
//  - `font.family`. QML takes one family, not a CSS-style fallback chain
//    (see Theme.fontFamily), so getting this wrong silently drops Latin text
//    onto a different, narrower face.
//  - a default `font.pixelSize`, so a site that doesn't care doesn't pick.
//
// Colour is deliberately *not* unified: the bar pills, the hover popups and
// the notification surfaces each have their own palette (Theme.groupText,
// Theme.text/textBright, NotificationTheme.text), so every site states it.
// Theme.text is only the fallback for a site that says nothing at all.
Text {
    renderType: Text.NativeRendering
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    color: Theme.text
}
