pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// Every piece of text in this shell, so the three things that are the same at
// all ~65 text sites aren't a convention someone has to remember:
//
//  - `renderType: Text.NativeRendering`. The default SDF renderer shows
//    visible chromatic fringing here and there is no global setting for it, so
//    a missed opt-in is a subtle rendering regression nobody would report.
//  - `font.family`. QML takes one family, not a fallback chain, and getting it
//    wrong silently drops Latin text onto a narrower face.
//  - a default `font.pixelSize`, so a site that doesn't care doesn't pick.
//
// Colour is deliberately not unified: the bar pills, hover popups and
// notification surfaces have separate palettes, so every site states it.
// Theme.text is only the fallback for a site that says nothing at all.
Text {
    renderType: Text.NativeRendering
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    color: Theme.text
}
