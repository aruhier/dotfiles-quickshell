import QtQuick
import Quickshell
import Quickshell.Widgets
import ".."

// Base type for a hover-triggered popup anchored below a bar module. Adds
// the background chrome, the show/hide grace timer, and PopupCoordinator
// registration on top of AnchoredPopupWindow's shared anchor math, so every
// popup built on this gets close() — and mutual exclusion with other
// popups — for free instead of by copy-paste convention (see
// Clock.qml/Weather.qml history). A module supplies its own content as
// default children and drives visibility by calling show()/requestHide()
// from its own hover MouseArea; it still sets implicitWidth/implicitHeight
// itself, since content sizing is genuinely per-module.
//
// shared/Tooltip.qml only shares the AnchoredPopupWindow base, not this
// type: that popup is driven by a declarative `show` boolean from many call
// sites and closes with no grace period at all (nothing to move the cursor
// onto) — a different enough contract that forcing it onto this
// show()/requestHide()/coordinator API would be a behavior change, not a
// refactor.
AnchoredPopupWindow {
    id: popup

    property int cornerRadius: 10
    property int padding: 14
    property int hideDelay: 200

    default property alias content: contentItem.data

    property bool _open: false
    // Tracks only the popup's own surface. Any renewed hover anywhere
    // (module or popup) calls show(), which stops hideTimer outright — so
    // by the time hideTimer actually fires, checking this alone is enough
    // to know nothing is hovering any more.
    property bool _popupHovered: false

    function show() {
        hideTimer.stop();
        PopupCoordinator.activate(popup);
        _open = true;
    }

    function requestHide() {
        hideTimer.restart();
    }

    // Called by PopupCoordinator on the previously-active popup when a
    // different one takes over — closes immediately, no grace period.
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
