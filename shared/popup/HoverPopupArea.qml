import QtQuick

// Hover MouseArea that opens a lazily-loaded HoverPopup: activates `loader`
// and calls show()/requestHide() on the loaded item. Shared by Clock.qml and
// Weather.qml, which both wire a LazyLoader-backed HoverPopup this same way
// (Weather also attaches its own onClicked on top, which works fine since
// this is still a plain MouseArea underneath).
MouseArea {
    id: area

    required property var loader

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: {
        if (containsMouse) {
            area.loader.active = true;
            area.loader.item.show();
        } else if (area.loader.item) {
            area.loader.item.requestHide();
        }
    }
}
