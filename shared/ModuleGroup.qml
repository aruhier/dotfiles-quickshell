pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.themes

// Flush pill-shaped module group for the bar's left/right ends: rounded on the
// side facing center, square against the screen edge. The center group is a
// floating RowLayout instead, in Bar.qml.
Rectangle {
    id: group

    property alias model: repeater.model
    required property var resolveComponent
    // Qt.LeftEdge or Qt.RightEdge: which screen edge this group sits against.
    required property int edge
    // Extra margin on the flush edge, on top of Theme.groupEdgePadding on the
    // inner one. Left and right differ — see Bar.qml.
    property real outerMargin: 0

    // Half the bar height, so the corners round into a full semicircle.
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
