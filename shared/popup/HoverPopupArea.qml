pragma ComponentBehavior: Bound
import QtQuick

// Hover area driving a lazily-loaded HoverPopup: activates `loader` after a
// dwell and mirrors its own hover into the loaded item's `anchorHovered`. Still
// a plain MouseArea, so a call site can attach its own onClicked on top
// (Weather.qml does).
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

    // Read this rather than containsMouse, which stays false here: hover is
    // tracked by the HoverHandler below, not the MouseArea.
    readonly property bool hovered: hover.hovered

    // For a click that makes the popup moot (Workspaces: switching to the
    // previewed workspace): drops a pending open and closes an open one.
    function cancel() {
        showTimer.stop();
        if (area.loader.item)
            area.loader.item.close();
    }

    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor

    // Hover via a HoverHandler rather than `hoverEnabled` on the MouseArea, for
    // the same reason as HoverPopup's surface: it then doesn't matter where in
    // a module's z-order this sits, or whether the module's content grows a
    // hover-tracking child of its own.
    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) {
                // Already built (cursor coming back from the popup surface):
                // no dwell, just report the hover so the popup's grace timer
                // stops. Otherwise dwell first; the timer builds it.
                if (area.loader.item)
                    area.loader.item.anchorHovered = true;
                else
                    showTimer.restart();
            } else {
                showTimer.stop();
                if (area.loader.item)
                    area.loader.item.anchorHovered = false;
            }
        }
    }

    Timer {
        id: showTimer
        interval: area.showDelay
        onTriggered: {
            if (!area.popupEnabled)
                return;
            area.loader.active = true;
            area.loader.item.anchorHovered = true;
        }
    }
}
