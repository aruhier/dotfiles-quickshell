pragma ComponentBehavior: Bound
import QtQuick

// Hover MouseArea driving a lazily-loaded HoverPopup: activates `loader` and
// calls show()/requestHide() on the loaded item. Still a plain MouseArea, so a
// call site can attach its own onClicked on top (Weather.qml does).
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
