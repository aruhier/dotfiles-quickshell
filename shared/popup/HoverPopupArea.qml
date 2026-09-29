pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.popup

// Hover area driving a lazily-loaded HoverPopup: activates `loader` after a
// dwell, mirrors its hover into the loaded item's `anchorHovered`, and tears
// the popup down when it closes. Still a plain MouseArea, so a call site can
// add its own onClicked.
//
// `loader` is a LazyLoader: HoverPopup is a window, not an Item. Torn down on
// close, since a popup window holds its GPU context (~3-4MB) for the life of
// the process — keyed on close(), not `visible`, which a subclass may gate so
// it never falls. Costs one frame on reopen.
MouseArea {
    id: area

    required property var loader

    property int showDelay: PopupCoordinator.hoverDwell

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

    // Safe mid-close(): LazyLoader destroys with deleteLater.
    Connections {
        target: area.loader.item
        function onDismissed() {
            area.loader.active = false;
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
