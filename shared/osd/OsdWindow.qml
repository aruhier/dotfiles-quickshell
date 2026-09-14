pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.shared
import qs.shared.animations
import qs.shared.notifications

// The on-screen display: one shared pill, bottom-centre on whichever output
// OsdService last targeted. Anchored to the screen rather than to a module, so
// it's a plain PanelWindow like the notification toasts, not the
// module-anchored machinery in ../popup/.
//
// Only the bottom edge is anchored: layer-shell centres a surface on the axis
// it isn't anchored to, so nothing here has to know the output's width. The
// surface sits flush with that edge and is taller than the pill, because the
// pill rises out of the edge on show and drops back under it on hide; the
// resting gap is room inside the surface rather than a layer-shell margin.
//
// Colours are NotificationTheme's, not Theme's: this is a floating surface
// over the desktop like a toast, and reading as one of those rather than as a
// detached bar pill is the point. Its metrics stay in Theme.qml with the rest
// of the shell's.
PanelWindow {
    id: osd

    readonly property bool showing: OsdService.kind !== ""

    // The last non-empty kind, not OsdService.kind itself: that goes back to ""
    // the moment the hide timer fires, while the window is still on screen for
    // the length of the exit spring, so binding the content to it directly
    // makes every OSD render the fallback branch of the switches below as it
    // slides out. Off the request rather than off `showing`, since one OSD can
    // replace another while the window is up and `showing` never drops.
    property string kind: ""
    readonly property string requestedKind: OsdService.kind
    onRequestedKindChanged: if (requestedKind !== "")
        kind = requestedKind

    // Volume and backlight draw a level track; a lock key has no level, so it
    // draws its state as a word instead.
    readonly property bool level: kind === "volume" || kind === "brightness"
    readonly property bool lockOn: !level && LockKeysService.state(kind)

    readonly property real value: kind === "volume" ? AudioService.pct / AudioService.maxPct : kind === "brightness" ? BacklightService.percent / 100 : 0

    readonly property string glyph: {
        switch (kind) {
        case "volume":
            return AudioService.icon;
        case "brightness":
            return BacklightService.icon;
        case "capslock":
            return "󰘲";
        case "numlock":
            return "󰎠";
        default:
            return "󰌌";
        }
    }

    readonly property string label: {
        switch (kind) {
        case "volume":
            return AudioService.muted ? "muted" : AudioService.pct + "%";
        case "brightness":
            return Math.round(BacklightService.percent) + "%";
        case "capslock":
            return osd.lockOn ? "Caps Lock on" : "Caps Lock off";
        case "numlock":
            return osd.lockOn ? "Num Lock on" : "Num Lock off";
        default:
            return osd.lockOn ? "Scroll Lock on" : "Scroll Lock off";
        }
    }

    // Both the height of the surface and the distance the pill covers: its own
    // height, plus the gap it rests above the bottom of the output. That gap is
    // snapped for the same reason as the toast stack's margins — an off-grid
    // offset puts every glyph below it on a fraction of a device pixel. See
    // AGENTS.md.
    readonly property real travel: Screens.snap((osd.screen ? osd.screen.height : 1080) * Theme.osdBottomEdgeFraction, osd.screen) + Theme.osdHeight

    anchors.bottom: true
    // The gap above is room inside the surface, not a layer-shell margin:
    // a margin would have to be animated to move the pill, and every frame of
    // that is a surface reconfigure.
    margins.bottom: 0

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Nothing here is clickable, and an overlay-layer surface with an input
    // region would swallow clicks meant for whatever is under it.
    mask: Region {}

    // The surface is centred by its width, so that width is what decides where
    // the left edge — and with it every glyph — lands on the device pixel grid.
    implicitWidth: Screens.snap(Theme.osdWidth, osd.screen)
    implicitHeight: osd.travel

    // Stays mapped until the exit spring has settled, then unmaps entirely so
    // nothing is left on the overlay layer between keypresses.
    visible: slide.value < osd.travel

    // The offset of the pill below its resting place, in pixels: `travel` is
    // off-screen, 0 is up. A pixel spring, so Theme.springEpsilon (pixel-scale)
    // applies as it stands — see PressSpring.qml for the 0..1 case.
    FrameSpring {
        id: slide
        to: osd.showing ? 0 : osd.travel
        // Much softer than Theme's defaults, which are tuned for the few
        // pixels a module's width moves and read as a snap over this
        // distance. Damping ratio a shade over 1, so the pill glides to the
        // edge and stops dead rather than bouncing: 90% of the travel in
        // ~265ms.
        stiffness: 150
        damping: 20
    }

    // OsdService picks the output before it sets the kind, so an OSD moving to
    // a screen of a different height changes `travel` while the pill is still
    // parked. Re-park it: left at the old offset it would start its rise from
    // the wrong place, and on a taller screen that place is already on-screen.
    onTravelChanged: if (!osd.showing)
        slide.snapTo(osd.travel)

    // The pill itself: `Theme.osdHeight` of the surface, sliding through the
    // rest of it. Moved by `y` and nothing else — never `layer`/MultiEffect or
    // an opacity fade over one, since a layer source is a texture and a
    // texture resamples the text inside it. See AGENTS.md.
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.osdHeight
        y: slide.value

        Rectangle {
            anchors.fill: parent
            radius: Theme.osdRadius
            // Real alpha, like the control centre's plate — the `quickshell-osd`
            // blur layerrule is what gives it something to show through. The
            // hue is the toasts', the opacity is Theme.osdOpacity; see there.
            color: Qt.rgba(NotificationTheme.bgFloating.r, NotificationTheme.bgFloating.g, NotificationTheme.bgFloating.b, Theme.osdOpacity)
            border.width: 1
            border.color: NotificationTheme.borderSubtle
        }

        // Level layout: glyph, track, percentage.
        Item {
            anchors.fill: parent
            visible: osd.level

            Icon {
                id: levelGlyph
                anchors.left: parent.left
                anchors.leftMargin: Theme.osdPadding
                anchors.verticalCenter: parent.verticalCenter
                // pixelSize over Icon's sizeRatio, as the notification
                // surfaces do: this one isn't sized against bar text.
                font.pixelSize: Theme.osdIconSize
                color: NotificationTheme.text
                text: osd.glyph
            }

            // A fixed slot, not the label's own width: the track would
            // otherwise resize under the number as it goes 9% -> 10% -> 100%.
            Item {
                id: valueSlot
                anchors.right: parent.right
                anchors.rightMargin: Theme.osdPadding
                anchors.verticalCenter: parent.verticalCenter
                width: widest.width
                height: valueLabel.implicitHeight

                TextMetrics {
                    id: widest
                    font: valueLabel.font
                    text: "100%"
                }

                StyledText {
                    id: valueLabel
                    anchors.right: parent.right
                    color: NotificationTheme.text
                    font.pixelSize: NotificationTheme.fontSize
                    text: osd.label
                }
            }

            Rectangle {
                anchors.left: levelGlyph.right
                anchors.leftMargin: Theme.osdPadding
                anchors.right: valueSlot.left
                anchors.rightMargin: Theme.osdPadding
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.osdTrackHeight
                radius: height / 2
                // A tint over the plate, not an absolute grey — see
                // NotificationTheme.bgOverlay.
                color: NotificationTheme.bgOverlay

                Rectangle {
                    // Never narrower than one cap: a 0% fill collapsed to
                    // nothing reads as a broken track rather than an empty one.
                    width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, osd.value)))
                    height: parent.height
                    radius: parent.radius
                    // A muted sink still has a level, but it isn't audible —
                    // the fill drops to the dim body colour rather than
                    // vanishing.
                    color: osd.kind === "volume" && AudioService.muted ? NotificationTheme.textDisabled : NotificationTheme.bgSelected
                }
            }
        }

        // Lock-key layout: glyph and state, centred as a pair.
        Row {
            anchors.centerIn: parent
            spacing: Theme.osdPadding
            visible: !osd.level

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Theme.osdIconSize
                // No level to carry the state, so the glyph does: accent when
                // the lock is on, dimmed when it's off.
                color: osd.lockOn ? NotificationTheme.bgSelected : NotificationTheme.textDisabled
                text: osd.glyph
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                color: osd.lockOn ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.fontSize
                text: osd.label
            }
        }
    }
}
