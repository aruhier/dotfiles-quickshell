pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.shared
import qs.shared.popup

// Battery indicator, a port of the waybar `battery` module this bar
// replaced (~/.config/waybar/config.d/common.json + style.css). Same
// three formats ({capacity}% + level icon / charging bolt / plug) and the
// same 30%-warning / 15%-critical thresholds. The one deliberate departure
// is what "critical" looks like — see blinkOpacity below.
//
// No dedicated service, for the same reason Privacy.qml doesn't have one:
// there's no owned I/O here to deduplicate across outputs — UPower is
// already a process-wide Quickshell singleton, and everything below is a
// pure derivation over it (same shape as Volume.qml reading
// Pipewire.defaultAudioSink per output). upower's own daemon does the
// polling, the multi-battery aggregation (`displayDevice`) and the
// time-remaining smoothing that waybar had to hand-roll over
// /sys/class/power_supply.
BarModule {
    id: root

    // Real laptop batteries only — UPower.devices also carries line-power
    // supplies (AC/USB-C/wireless here) and peripheral batteries.
    readonly property var batteries: UPower.devices.values.filter(dev => dev.isLaptopBattery)
    // upower's aggregate across every battery, equivalent to waybar's
    // total_energy/total_energy_full sum. Health/cycle counts aren't on it,
    // so the tooltip reads those off the first real battery instead.
    readonly property var device: UPower.displayDevice
    readonly property var mainBattery: batteries.length > 0 ? batteries[0] : null

    contentVisible: batteries.length > 0 && device !== null && device.ready

    // Quickshell normalizes UPowerDevice.percentage to 0..1, unlike
    // upower's own D-Bus property (0..100).
    readonly property int percent: device && device.ready ? Math.min(100, Math.round(device.percentage * 100)) : 0

    // Named `deviceState`, not `state`: `state` is QQuickItem's own
    // (string) property driving QML's states/transitions system — declaring
    // an int over it shadows a built-in.
    readonly property int deviceState: device && device.ready ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: deviceState === UPowerDeviceState.Charging
    readonly property bool full: deviceState === UPowerDeviceState.FullyCharged
    // waybar's "Plugged": on the adapter but not actually charging — which
    // is the steady state on this machine, since it stops at the battery's
    // 80% charge-end threshold (UPower reports PendingCharge for that).
    readonly property bool plugged: !charging && !full && !UPower.onBattery

    // waybar's `states` config, resolved the way ALabel::getState does it
    // (thresholds sorted ascending, first one the capacity is <= wins).
    readonly property string level: percent <= 15 ? "critical" : percent <= 30 ? "warning" : ""

    // waybar's `#battery.critical:not(.charging)` condition — charging out
    // of a critical level isn't an emergency, so it doesn't blink. What the
    // state actually looks like here differs; see blinkOpacity below.
    readonly property bool criticalBlink: level === "critical" && !charging

    // ---- icons ----
    // waybar's format-icons array, indexed by ALabel::getIcon's
    // `capacity / (100 / size)` clamped to the last entry: 0-19, 20-39,
    // 40-59, 60-79, 80-100.
    readonly property var levelIcons: ["󰂎", "󰁼", "󰁿", "󰂁", "󰁹"]
    readonly property string icon: charging ? "󰂄" : plugged ? "󰚥" : levelIcons[Math.min(levelIcons.length - 1, Math.floor(percent / 20))]

    // The Material Design battery/plug glyphs are drawn upright (nub on
    // top); waybar rotates them into the usual horizontal battery with
    // Pango's `gravity='west'` (= 90° clockwise). It does that on the level
    // and plugged icons but *not* on the charging bolt, so the bolt stands
    // upright there — reproduced as-is. Flip this to `true` if you'd rather
    // have all three consistent.
    readonly property bool rotateIcon: !charging

    // ---- time remaining ----
    // Seconds until empty/full, straight off upower (which already smooths
    // the rate — waybar hand-rolled an EMA over power_now for this). 0 when
    // it can't tell yet, e.g. just after plugging in.
    readonly property real secondsRemaining: {
        if (!device || !device.ready)
            return 0;
        if (charging)
            return device.timeToFull;
        if (deviceState === UPowerDeviceState.Discharging || deviceState === UPowerDeviceState.PendingDischarge)
            return device.timeToEmpty;
        return 0;
    }

    // waybar's formatTimeRemaining(): "{H} h {M} min", both parts always
    // shown, empty string when it rounds down to nothing.
    function formatDuration(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (hours === 0 && minutes === 0)
            return "";
        return hours + " h " + minutes + " min";
    }

    readonly property string statusText: {
        if (charging)
            return "Charging";
        if (full)
            return "Full";
        if (plugged)
            return "Plugged";
        if (deviceState === UPowerDeviceState.Empty)
            return "Empty";
        if (deviceState === UPowerDeviceState.Discharging || deviceState === UPowerDeviceState.PendingDischarge)
            return "Discharging";
        return "Unknown";
    }

    // waybar's default `{timeTo}` tooltip: the estimate when there is one,
    // the plain status when there isn't.
    readonly property string estimateText: {
        const formatted = root.formatDuration(root.secondsRemaining);
        if (formatted === "")
            return root.statusText;
        return (root.charging ? "Full in " : "Empty in ") + formatted;
    }

    // waybar's other tooltip args ({power}, {health}) on a second line —
    // health comes off the battery itself, since the aggregate display
    // device doesn't carry energy-full-design.
    readonly property string detailText: {
        var parts = [];
        if (device && device.ready && Math.abs(device.changeRate) >= 0.05)
            parts.push(Math.abs(device.changeRate).toFixed(1) + " W");
        if (mainBattery && mainBattery.ready && mainBattery.healthSupported && mainBattery.healthPercentage > 0)
            parts.push("Health " + Math.round(mainBattery.healthPercentage) + "%");
        return parts.join("  ·  ");
    }

    contentWidth: content.implicitWidth

    // Icon vertical nudge / size bias — see Mpd.qml. The rotated glyph
    // needs a different nudge from the upright bolt, mirroring the two
    // different baseline_shift/rise pairs waybar's format strings carry.
    readonly property real iconVerticalOffset: rotateIcon ? 0 : 1
    readonly property real iconSizeRatio: 1.0

    // Deliberately *not* style.css's `#battery.critical:not(.charging)`
    // rule (the whole module's background going red and blinking to white
    // twice a second): a solid block of color fights the pill-shaped groups
    // this bar is built out of, and it blinks fast enough to be a
    // distraction rather than a warning. Same signal in a quieter form —
    // the label and icon turn red and pulse slowly, so the module keeps its
    // shape and the bar keeps its palette.
    //
    // The pulse bottoms out at 0.6, not near-invisible: opacity fades
    // toward the background, so a deep trough costs exactly the contrast
    // the warning needs (Theme.critical is 4.4:1 on groupBg at full
    // opacity, 1.6:1 at 0.3). The label also goes bold in this state,
    // which carries more of the signal than the fade does.
    property real blinkOpacity: 1
    readonly property color textColor: criticalBlink ? Theme.critical : Theme.groupText

    SequentialAnimation {
        running: root.criticalBlink
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "blinkOpacity"
            from: 1
            to: 0.6
            duration: 1200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: root
            property: "blinkOpacity"
            from: 0.6
            to: 1
            duration: 1200
            easing.type: Easing.InOutSine
        }
    }

    // The animation stops mid-pulse when the state clears (charger plugged
    // in), leaving blinkOpacity wherever it was — which would then be the
    // module's permanent opacity, since nothing else drives it.
    onCriticalBlinkChanged: {
        if (!criticalBlink)
            blinkOpacity = 1;
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6
        // Whole row, not per-Text: the percentage and the icon have to pulse
        // together or they read as two separate blinking things.
        opacity: root.blinkOpacity

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            // Bold only on the label, not the glyph: the Nerd Font fallback
            // has no bold face, so Qt would synthesize a smeared one.
            // `font.weight`, not `font.bold` — Inter is a variable font and
            // Qt picks its weight axis by number.
            font.weight: root.criticalBlink ? Font.Bold : Font.Normal
            color: root.textColor
            text: root.percent + "%"
        }

        // `rotation` doesn't affect an item's implicit size, so the glyph
        // needs a wrapper to reserve the space its rotated form actually
        // occupies — otherwise the Row lays it out at the upright width and
        // the neighbours overlap it.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            // Sized off TextMetrics' *tight* (ink) bounding rect when
            // rotated, not the swapped implicitWidth/implicitHeight: those
            // are the layout box (advance width, ascent+descent line
            // height), and the line box is ~5px taller than these glyphs'
            // ink — reserving it as width left a visibly wider label/icon
            // gap here than every other module's 6px. The ink rect is
            // vertically centered in the line box for this font, so
            // rotating about the wrapper's center lands it centered
            // horizontally with no further correction.
            implicitWidth: root.rotateIcon ? iconMetrics.tightBoundingRect.height : glyph.implicitWidth
            implicitHeight: root.rotateIcon ? iconMetrics.tightBoundingRect.width : glyph.implicitHeight

            TextMetrics {
                id: iconMetrics
                font: glyph.font
                text: glyph.text
            }

            Icon {
                id: glyph
                anchors.centerIn: parent
                rotation: root.rotateIcon ? 90 : 0
                sizeRatio: root.iconSizeRatio
                color: root.textColor
                text: root.icon
            }
        }
    }

    // Hover state tracked by hand rather than via HoverPopupArea: that type
    // drives HoverPopup's show()/requestHide() API, and Tooltip is the
    // other kind of popup (declarative `show`, no grace period) — same
    // wiring Tray.qml uses.
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
    }

    // LazyLoader, not Loader: Tooltip is a PopupWindow, not an Item — see
    // Clock.qml's popupLoader for the rationale.
    LazyLoader {
        active: hover.containsMouse && root.contentVisible

        Tooltip {
            anchorItem: root
            show: hover.containsMouse && root.contentVisible
            text: root.detailText === "" ? root.estimateText : root.estimateText + "<br>" + root.detailText
        }
    }
}
