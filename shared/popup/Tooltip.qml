pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup

// Small hover tooltip anchored below a bar module. Opens after a `showDelay`
// dwell and closes immediately — unlike HoverPopup, there's nothing here to
// move the cursor onto, so it needs no grace period.
AnchoredPopupWindow {
    id: popup

    property string text: ""
    property bool show: false
    property int maxWidth: 480

    // Dwell before showing, so a cursor crossing the bar doesn't flash
    // tooltips open. `show` is the request, `_dwelled` the timer's answer.
    property int showDelay: 500

    property bool _dwelled: false

    visible: show && _dwelled && text.length > 0

    // `running`, not an onShowChanged restart: `show` is usually already true
    // when the LazyLoader builds this, so the handler would never fire.
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
