pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// The module groups against one screen edge: one ModuleGroup per entry of
// `groups`, laid out from the screen edge inward and overlapping by a cap
// radius, so each group slides out from under the previous one's rounded
// end. A group with nothing to show is left out entirely and the rest close
// up — a Row skips hidden children.
Row {
    id: strip

    // One layout entry per group, from shell.qml; ModuleGroup reads them.
    required property var groups
    required property var resolveComponent
    // Qt.LeftEdge or Qt.RightEdge.
    required property int edge
    property real outerMargin: 0

    anchors.left: edge === Qt.RightEdge ? undefined : parent.left
    anchors.right: edge === Qt.RightEdge ? parent.right : undefined
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    // Item 0 is always the one against the screen.
    layoutDirection: edge === Qt.RightEdge ? Qt.RightToLeft : Qt.LeftToRight
    // Negative: the next group starts under the previous one's cap.
    spacing: -height / 2

    Repeater {
        model: strip.groups
        delegate: ModuleGroup {
            required property var modelData
            spec: modelData
            edge: strip.edge
            outerMargin: strip.outerMargin
            resolveComponent: strip.resolveComponent
        }
    }
}
