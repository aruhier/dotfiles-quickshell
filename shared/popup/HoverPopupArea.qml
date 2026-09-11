pragma ComponentBehavior: Bound
import QtQuick

// Hover MouseArea driving a lazily-loaded HoverPopup: activates `loader` and
// calls show()/requestHide() on the loaded item. Still a plain MouseArea, so a
// call site can attach its own onClicked on top (Weather.qml does).
MouseArea {
    id: area

    required property var loader

    // Grace before a hover opens the popup, so a cursor merely crossing the
    // bar neither flashes popups open nor pays for building them: the loader
    // stays inactive until the timer fires.
    property int showDelay: 500

    // False when there is nothing to show (Workspaces: an empty workspace):
    // hover then never activates the loader at all, instead of building a
    // popup that stays invisible and lingers until its next hover.
    property bool popupEnabled: true

    // For a click that makes the popup moot (Workspaces: switching to the
    // previewed workspace): drops a pending open and closes an open one.
    function cancel() {
        showTimer.stop();
        if (area.loader.item)
            area.loader.item.close();
    }

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: {
        if (containsMouse) {
            // Coming back from the popup's own surface: it is already open and
            // its hideTimer is running, so cancel that now rather than after
            // another showDelay — by then the popup would have closed under a
            // cursor that never left the module.
            if (area.loader.item && area.loader.item._open)
                area.loader.item.show();
            else
                showTimer.restart();
        } else {
            showTimer.stop();
            if (area.loader.item)
                area.loader.item.requestHide();
        }
    }

    Timer {
        id: showTimer
        interval: area.showDelay
        onTriggered: {
            if (!area.popupEnabled)
                return;
            area.loader.active = true;
            area.loader.item.show();
        }
    }
}
