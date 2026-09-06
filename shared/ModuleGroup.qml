pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.shared

// Flush pill-shaped module group for the bar's left/right ends: rounded only
// on the side facing center, square on the side flush against the screen
// edge. Center doesn't use this: it's a floating RowLayout, not a pill (see
// Bar.qml).
Rectangle {
    id: group

    property alias model: repeater.model
    required property var resolveComponent
    // Qt.LeftEdge or Qt.RightEdge — which screen edge this group sits flush
    // against.
    required property int edge
    // Extra margin on the flush (outer) edge, beyond Theme.groupEdgePadding
    // on the inner (center-facing) edge. Left/right need different values
    // here since a module's own glyph bearing can already cover some of it
    // — see Bar.qml's callers.
    property real outerMargin: 0

    // Half the bar height, so the two center-facing corners round into a
    // full semicircle instead of a partial curve.
    readonly property real innerRadius: height / 2

    color: Theme.groupBg
    topLeftRadius: edge === Qt.RightEdge ? innerRadius : 0
    bottomLeftRadius: edge === Qt.RightEdge ? innerRadius : 0
    topRightRadius: edge === Qt.RightEdge ? 0 : innerRadius
    bottomRightRadius: edge === Qt.RightEdge ? 0 : innerRadius

    anchors.left: edge === Qt.RightEdge ? undefined : parent.left
    anchors.right: edge === Qt.RightEdge ? parent.right : undefined
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    implicitWidth: row.implicitWidth + Theme.groupEdgePadding + (edge === Qt.RightEdge ? outerMargin : 0)
    visible: row.implicitWidth > 0

    RowLayout {
        id: row
        anchors.left: group.edge === Qt.RightEdge ? undefined : parent.left
        anchors.right: group.edge === Qt.RightEdge ? parent.right : undefined
        anchors.rightMargin: group.edge === Qt.RightEdge ? group.outerMargin : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            id: repeater
            delegate: ModuleLoader { resolveComponent: group.resolveComponent }
        }
    }
}
