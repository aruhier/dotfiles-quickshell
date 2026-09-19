pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations
import qs.themes

// One module group: a coloured pill in the strip ModuleGroupRow builds
// against a screen edge. Rounded on the end facing center, square on the
// other: flush against the screen for the first group, and tucked under the
// previous group's rounded cap for the rest, so the cap stays visible as the
// separator (draw order: earlier groups on top). Which group is first
// depends on which are showing — a Row leaves hidden children out of its
// ordering, so `Positioner` tracks the visible strip for free.
//
// A group whose modules all hide springs its width to zero and back, clipped,
// so it slides in and out from under the previous group's cap (the submap
// group). While showing, its width follows the content directly: the modules
// already ease their own widths, and a spring chasing a spring would lag.
Rectangle {
    id: group

    // One entry of shell.qml's layout: {modules: [names], color?, textColor?}.
    // The only place that reads that shape.
    required property var spec
    required property var resolveComponent
    // Qt.LeftEdge or Qt.RightEdge: which screen edge the strip sits against.
    required property int edge
    // Extra margin on the flush edge, on top of Theme.groupEdgePadding on the
    // inner one. Left and right differ — see Bar.qml.
    property real outerMargin: 0

    readonly property bool flushLeft: edge === Qt.LeftEdge
    // The strip lays out from the screen edge inward, so its first item is
    // the one against the screen.
    readonly property bool atEdge: group.Positioner.isFirstItem

    // Half the bar height, so the cap rounds into a full semicircle.
    readonly property real capRadius: height / 2
    readonly property real leftRadius: flushLeft ? 0 : capRadius
    readonly property real rightRadius: flushLeft ? capRadius : 0
    // A tucked group pads past the cap it sits under, then the usual inner
    // padding, so its text is as far from the cap as the previous group's.
    readonly property real edgePadding: atEdge ? outerMargin : capRadius + Theme.groupEdgePadding
    readonly property real leftPadding: flushLeft ? edgePadding : Theme.groupEdgePadding
    readonly property real rightPadding: flushLeft ? Theme.groupEdgePadding : edgePadding

    readonly property bool hasContent: row.hasContent
    readonly property bool collapsing: !hasContent && widthSpring.running
    readonly property real naturalWidth: leftPadding + row.implicitWidth + rightPadding

    // Imperative rather than a `to` binding: while showing, a content change
    // snaps (no chase) unless a show is still in flight, in which case the
    // spring just takes the new target.
    onHasContentChanged: widthSpring.retarget(hasContent ? naturalWidth : 0)
    onNaturalWidthChanged: if (hasContent) {
        if (widthSpring.running)
            widthSpring.retarget(naturalWidth);
        else
            widthSpring.snapTo(naturalWidth);
    }
    Component.onCompleted: widthSpring.snapTo(hasContent ? naturalWidth : 0)

    color: spec.color ?? Theme.groupBg
    topLeftRadius: leftRadius
    bottomLeftRadius: leftRadius
    topRightRadius: rightRadius
    bottomRightRadius: rightRadius
    z: -group.Positioner.index
    clip: true

    anchors.top: parent.top
    anchors.bottom: parent.bottom

    implicitWidth: widthSpring.value
    // Hidden outright, not shrunk to an empty pill, once nothing in it shows
    // and the collapse has finished.
    visible: hasContent || widthSpring.running

    FrameSpring {
        id: widthSpring
    }

    ModuleRow {
        id: row
        model: group.spec.modules
        resolveComponent: group.resolveComponent
        textColor: group.spec.textColor ?? Theme.groupText
        keepShown: group.collapsing
        // Anchored to the screen-edge side, not centered: the two paddings
        // differ, and the collapse should retract toward that edge.
        anchors.left: group.flushLeft ? parent.left : undefined
        anchors.right: group.flushLeft ? undefined : parent.right
        anchors.leftMargin: group.leftPadding
        anchors.rightMargin: group.rightPadding
        anchors.verticalCenter: parent.verticalCenter
    }
}
