pragma ComponentBehavior: Bound
import QtQuick

// Hover area driving a lazily-loaded HoverPopup: activates `loader` after a
// dwell and mirrors its hover into the loaded item's `anchorHovered`. Still a
// plain MouseArea, so a call site can add its own onClicked.
MouseArea {
    id: area

    required property var loader

    // Dwell before opening, so a cursor crossing the bar neither flashes
    // popups open nor pays to build them.
    property int showDelay: 500

    // False when there's nothing to show (an empty workspace), so hover never
    // builds a popup that would only stay invisible.
    property bool popupEnabled: true

    // Not containsMouse, which stays false: the HoverHandler below tracks it.
    readonly property bool hovered: hover.hovered

    // For a click that makes the popup moot: drops a pending open and closes
    // an open one.
    function cancel() {
        showTimer.stop();
        if (area.loader.item)
            area.loader.item.close();
    }

    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor

    // A HoverHandler, not `hoverEnabled` — same reason as HoverPopup's
    // surface: z-order and hover-tracking children then don't matter.
    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) {
                // Already built (cursor returning from the popup): report the
                // hover to stop its grace timer, no second dwell.
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
