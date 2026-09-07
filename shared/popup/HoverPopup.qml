pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup

// Base type for a hover-triggered popup below a bar module: adds the
// background chrome, the close grace timer and PopupCoordinator registration
// on top of AnchoredPopupWindow's anchor math, so every popup gets close() and
// mutual exclusion for free. A module supplies content as default children,
// drives visibility with show()/requestHide() from its own hover MouseArea,
// and still sets implicitWidth/implicitHeight itself.
//
// Tooltip.qml shares only AnchoredPopupWindow, not this: it's driven by a
// declarative `show` bool and closes with no grace period, a different enough
// contract that forcing it onto this API would be a behavior change.
AnchoredPopupWindow {
    id: popup

    property int cornerRadius: 10
    property int padding: 14
    property int hideDelay: 200

    default property alias content: contentItem.data

    property bool _open: false
    // Only the popup's own surface. Any renewed hover, on the module or the
    // popup, calls show() and stops hideTimer — so by the time hideTimer
    // fires, this alone tells us nothing is hovered any more.
    property bool _popupHovered: false

    function show() {
        hideTimer.stop();
        PopupCoordinator.activate(popup);
        _open = true;
    }

    function requestHide() {
        hideTimer.restart();
    }

    // Called by PopupCoordinator on the previously-active popup when another
    // takes over: closes immediately, no grace period.
    function close() {
        hideTimer.stop();
        _open = false;
    }

    Timer {
        id: hideTimer
        interval: popup.hideDelay
        onTriggered: {
            if (!popup._popupHovered) {
                popup._open = false;
                PopupCoordinator.deactivate(popup);
            }
        }
    }

    visible: _open

    Rectangle {
        anchors.fill: parent
        color: "#1e1e1e"
        border.color: Theme.accent
        border.width: 1
        radius: popup.cornerRadius

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: {
                popup._popupHovered = containsMouse;
                if (containsMouse)
                    popup.show();
                else
                    popup.requestHide();
            }
        }

        Item {
            id: contentItem
            anchors.fill: parent
            anchors.margins: popup.padding
        }
    }
}
