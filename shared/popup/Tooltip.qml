pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup

// Small hover tooltip anchored below a bar module. Opens after a `showDelay`
// dwell like HoverPopupArea does for popups, but has no grace-period timer on
// the way out, unlike HoverPopup: it's plain text with nothing to move the
// cursor onto, so it closes immediately.
AnchoredPopupWindow {
    id: popup

    property string text: ""
    property bool show: false
    property int maxWidth: 480

    // Grace before a hover shows the tooltip, matching HoverPopupArea's
    // showDelay: a cursor merely crossing the bar shouldn't flash tooltips
    // open. `show` is the request, `_dwelled` the timer's answer to it.
    property int showDelay: 500

    property bool _dwelled: false

    visible: show && _dwelled && text.length > 0

    // `running`, not an onShowChanged restart: callers bind `show` to a hover
    // that is already true when the LazyLoader builds us, and a binding
    // evaluated at completion starts the timer where a change handler that
    // never fires would not.
    Timer {
        interval: popup.showDelay
        running: popup.show
        onTriggered: popup._dwelled = true
    }

    // Re-arm for the next hover: the loader usually destroys us first, but
    // Tray.qml keeps one tooltip alive across icons.
    onShowChanged: {
        if (!show)
            popup._dwelled = false;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.popupBg
        border.color: Theme.accent
        border.width: 1
        radius: 6

        StyledText {
            id: label
            anchors.fill: parent
            anchors.margins: 10
            text: popup.text
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            color: Theme.groupText
            font.pixelSize: Theme.fontSize
        }
    }

    // Math.ceil, not round/floor: a PopupWindow's surface is integer-pixel,
    // and rounding label metrics down clips a sub-pixel sliver off the border.
    implicitWidth: Math.ceil(Math.min(label.implicitWidth, maxWidth) + 20)
    implicitHeight: Math.ceil(label.implicitHeight + 16)
}
