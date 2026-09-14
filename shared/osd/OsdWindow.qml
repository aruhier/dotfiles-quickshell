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

    // The two widths the pill springs between. Collapsed is the glyph and its
    // padding and nothing else, so the glyph sits dead centre of it whatever
    // the icon's advance is; open is the full plate — fixed for a level, and
    // hugging the word for a lock key, which has no track to fill.
    readonly property real collapsedWidth: Screens.snap(2 * Theme.osdPadding + glyph.width, osd.screen)
    readonly property real openWidth: Screens.snap(osd.level ? Theme.osdWidth : 3 * Theme.osdPadding + glyph.width + lockLabel.implicitWidth, osd.screen)

    // How far along the expansion the pill is, 0..1. Drives the reveal of
    // everything past the glyph.
    readonly property real opened: Theme.ramp(expand.value, osd.collapsedWidth, osd.openWidth)

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
    // Wider than the widest pill by `osdOvershoot`, which is the room the
    // expansion spring needs to overshoot into: a window clips its contents.
    implicitWidth: Screens.snap(Theme.osdWidth + Theme.osdOvershoot, osd.screen)
    // Same slack again above the pill's resting place, for the rise to bump
    // into. `travel` stays the distance the pill covers, not the surface's
    // height, so nothing else here has to know about the extra room.
    implicitHeight: osd.travel + Theme.osdOvershoot

    // Stays mapped until the exit spring has settled, then unmaps entirely so
    // nothing is left on the overlay layer between keypresses.
    visible: slide.value < osd.travel

    // The entry is two stages: the bare glyph rises out of the edge, then the
    // pill widens around it. The exit reverses both. Each stage waits on the
    // other's spring rather than on a timer, so an OSD re-shown mid-exit
    // reverses from wherever it got to.
    //
    // `risen` the moment the pill first reaches its resting line, which is
    // before it has settled: the rise overshoots past that line and the
    // widening starts into the bump, so the two read as one gesture. A latch
    // rather than a comparison, because the rise then oscillates around the
    // line — a plain `slide.value <= 0` collapses the pill again on the first
    // dip below it, and the two springs fight.
    property bool risen: false
    // Latched when the wind-up before the drop has reached its bump height.
    // Starts true so a freshly loaded shell parks the pill below the edge
    // instead of winding up into view.
    property bool wound: true
    onShowingChanged: {
        risen = osd.showing && slide.value <= 0;
        if (osd.showing)
            wound = false;
    }
    // Deliberately far from 0: the hop has to start while the plate is still
    // visibly closing, or the exit reads as three separate beats where the
    // entry reads as one. The entry overlaps because the widening starts into
    // the rise's bump and runs through the whole of its settling; this is the
    // mirror of that, and at a fifth of the way open the width is still moving
    // ~7px a frame.
    readonly property bool narrowed: osd.opened <= 0.2

    // The offset of the pill below its resting place, in pixels: `travel` is
    // off-screen, 0 is up. A pixel spring, so Theme.springEpsilon (pixel-scale)
    // applies as it stands — see PressSpring.qml for the 0..1 case.
    FrameSpring {
        id: slide
        // Latches each stage the moment the pill reaches it; both are cleared
        // by onShowingChanged. The third branch parks the drop: it is aimed
        // past the edge, so once the pill is under it there is nothing left to
        // animate, and the next rise has to start from the edge itself.
        onValueChanged: {
            if (osd.showing && slide.value <= 0)
                osd.risen = true;
            else if (!osd.showing && osd.narrowed && slide.value <= -Theme.osdBump)
                osd.wound = true;
            else if (!osd.showing && osd.wound && slide.value >= osd.travel)
                slide.snapTo(osd.travel);
        }
        // Up while the OSD is showing or still narrowing, then a wind-up above
        // the resting place, then down. Both of the latter are aimed past
        // where the pill actually goes, since a latch stops it: the wind-up's
        // multiplier is not the hop's height but its speed (half again past
        // `osdBump` puts the apex at ~150ms, where 2.5x reached the same 18px
        // in ~95 and read as a flick), and the drop aims below the edge so the
        // pill is still moving when it crosses it. Aimed at the edge exactly,
        // a spring decelerates into it and the last sliver creeps away for a
        // third of a second.
        to: osd.showing || !osd.narrowed ? 0 : osd.wound ? osd.travel * 1.5 : -Theme.osdBump * 1.5
        // Much softer than Theme's defaults, which are tuned for the few
        // pixels a module's width moves and read as a snap over this
        // distance. Under damped on the way up (ratio ~0.68) so the pill bumps
        // a few pixels past its resting place — the room for that is
        // Theme.osdOvershoot — and damped past 1 on the way down, where an
        // undershoot would drop the pill below the screen and bounce it back
        // into view.
        stiffness: 136
        damping: osd.showing ? 12.3 : 18.2
    }

    // The width of the pill. Under damped on the way open — the overshoot and
    // settle-back is the spring in the expansion, ~3% of the travel, which is
    // the room Theme.osdOvershoot leaves. Damped past 1 on the way closed,
    // where undershooting would narrow the plate past its own glyph.
    FrameSpring {
        id: expand
        to: osd.risen ? osd.openWidth : osd.collapsedWidth
        stiffness: 215
        damping: osd.risen ? 16.5 : 24
    }

    // OsdService picks the output before it sets the kind, so an OSD moving to
    // a screen of a different height changes `travel` while the pill is still
    // parked. Re-park it: left at the old offset it would start its rise from
    // the wrong place, and on a taller screen that place is already on-screen.
    onTravelChanged: if (!osd.showing)
        slide.snapTo(osd.travel)

    // The pill itself: `Theme.osdHeight` of the surface, sliding through the
    // rest of it. Moved by `x`/`y`/`width` and nothing else — never
    // `layer`/MultiEffect or an opacity fade over one, since a layer source is
    // a texture and a texture resamples the text inside it. See AGENTS.md.
    Item {
        id: pill

        // Centred in the surface, so the pill grows out of its own middle. The
        // snap keeps both edges of the 1px border on the device pixel grid at
        // rest, whatever width the kind settled on.
        width: expand.value
        x: Screens.snap((parent.width - width) / 2, osd.screen)
        height: Theme.osdHeight
        // `slide` is the offset below the resting place, so the resting place
        // itself is the slack the bump needs above it.
        y: Theme.osdOvershoot + slide.value

        Rectangle {
            anchors.fill: parent
            radius: Theme.osdRadius
            // Real alpha, like the control centre's plate — the `quickshell-osd`
            // blur layerrule is what gives it something to show through. The
            // toasts' plate colour outright, alpha included: both are floating
            // surfaces over the desktop and read as one material.
            color: NotificationTheme.bgFloating
            border.width: 1
            border.color: NotificationTheme.borderSubtle
        }

        // The one thing the collapsed pill shows, so it belongs to the pill
        // rather than to either layout below.
        Icon {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.osdPadding
            anchors.verticalCenter: parent.verticalCenter
            // pixelSize over Icon's sizeRatio, as the notification
            // surfaces do: this one isn't sized against bar text.
            font.pixelSize: Theme.osdIconSize
            // A level carries its own state in the track, so its glyph is just
            // a label; a lock key has nothing else to carry it, so the glyph
            // goes accent when on and dims when off.
            color: osd.level ? NotificationTheme.text : osd.lockOn ? NotificationTheme.bgSelected : NotificationTheme.textDisabled
            text: osd.glyph
        }

        // Everything past the glyph, in the space the expansion opens up. Held
        // back to the second half of it so the plate is visibly a plate before
        // anything is written on it, and not rendered at all before that —
        // which is also what keeps the level layout from reflowing through the
        // widths where its track has no room.
        Item {
            id: detail

            anchors.left: glyph.right
            anchors.leftMargin: Theme.osdPadding
            anchors.right: parent.right
            anchors.rightMargin: Theme.osdPadding
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            opacity: Theme.ramp(osd.opened, 0.45, 0.80)
            visible: opacity > 0

            // Level layout: track, then percentage.
            Item {
                anchors.fill: parent
                visible: osd.level

                // A fixed slot, not the label's own width: the track would
                // otherwise resize under the number as it goes 9% -> 10% -> 100%.
                Item {
                    id: valueSlot
                    anchors.right: parent.right
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
                    anchors.left: parent.left
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
                        width: Math.max(parent.height, parent.width * Theme.clamp01(osd.value))
                        height: parent.height
                        radius: parent.radius
                        // A muted sink still has a level, but it isn't audible —
                        // the fill drops to the dim body colour rather than
                        // vanishing.
                        color: osd.kind === "volume" && AudioService.muted ? NotificationTheme.textDisabled : NotificationTheme.bgSelected
                    }
                }
            }

            // Lock-key layout: the state as a word, which `openWidth` sizes
            // the open pill to. An invisible Text still reports its
            // implicitWidth, so that width is known before the pill opens.
            StyledText {
                id: lockLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !osd.level
                color: osd.lockOn ? NotificationTheme.text : NotificationTheme.textDisabled
                font.pixelSize: NotificationTheme.fontSize
                text: osd.label
            }
        }
    }
}
