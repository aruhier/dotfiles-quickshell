import QtQuick
import "../services"
import "../shared"
import "../shared/animations"

// Screen-brightness indicator. Actual /sys/class/backlight polling lives in
// services/BacklightService.qml (singleton, one poll cycle for the whole
// process regardless of monitor count); this is just a thin view over that
// shared state. Hides itself when there's no backlight device (e.g. external
// monitors).
Item {
    id: root

    readonly property real percent: BacklightService.percent
    readonly property bool available: BacklightService.available

    // Plain bool, not read back through `visible` — see Mpd.qml's
    // `contentVisible` for why (Loader/visible deadlock).
    readonly property bool contentVisible: available
    visible: contentVisible
    // Unconditional, not gated on `available`: see Mpd.qml for why gating
    // width on the same property as `visible` breaks visibility.
    readonly property real targetWidth: content.implicitWidth + 12
    implicitWidth: widthSpring.value
    implicitHeight: Theme.barHeight
    clip: true

    // FrameSpring, not Behavior/WidthSpring — see Submap.qml's FrameSpring
    // for why (Behavior-based SpringAnimation is throttled to Qt Quick's
    // shared ~60Hz GUI-thread clock regardless of the output's real refresh
    // rate).
    FrameSpring {
        id: widthSpring
        Component.onCompleted: snapTo(root.targetWidth)
    }

    onTargetWidthChanged: widthSpring.retarget(targetWidth)

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 2
    readonly property real iconSizeRatio: 1.0

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.groupText
            text: Math.round(root.percent) + "%"
        }

        Text {
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize(root.iconSizeRatio)
            color: Theme.groupText
            text: root.percent < 50 ? "󰃞" : "󰃠"
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (!root.available)
                return;
            BacklightService.bump(event.angleDelta.y > 0 ? "+5%" : "5%-");
        }
    }
}
