pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.shared.popup

// A Tooltip built only while `show` holds. A LazyLoader, not a Loader: Tooltip
// is a PopupWindow, not an Item. It has no close grace period, so `active` can
// mirror `show` with no teardown hook.
LazyLoader {
    id: loader

    property bool show: false
    property Item anchorItem: null
    property string text: ""

    active: loader.show

    Tooltip {
        anchorItem: loader.anchorItem
        show: loader.show
        text: loader.text
    }
}
