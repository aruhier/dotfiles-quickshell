pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.popup
import qs.themes

// Small hover tooltip anchored below a bar module. Opens after a `showDelay`
// dwell and closes immediately — unlike HoverPopup, there's nothing here to
// move the cursor onto, so it needs no grace period.
AnchoredPopupWindow {
    id: popup

    property string text: ""
    property bool show: false
    property int maxWidth: 480
    property int padding: 10

    // `show` is the request, `_dwelled` the dwell timer's answer.
    property int showDelay: PopupCoordinator.hoverDwell

    property bool _dwelled: false

    visible: show && _dwelled && text.length > 0

    // `running`, not an onShowChanged restart: `show` is usually already true
    // when the LazyLoader builds this, so the handler would never fire.
    Timer {
        interval: popup.showDelay
        running: popup.show
        onTriggered: popup._dwelled = true
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
            anchors.margins: popup.padding
            text: popup.text
            wrapMode: Text.WordWrap
            color: Theme.groupText
            font.pixelSize: Theme.fontSize
        }
    }

    wantedWidth: Math.min(label.implicitWidth, maxWidth) + 2 * padding
    wantedHeight: label.implicitHeight + 2 * padding
}
