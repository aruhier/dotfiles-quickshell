pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.shared
import qs.shared.popup

// Battery indicator, a port of the waybar `battery` module this bar replaced:
// same three formats ({capacity}% + level icon / charging bolt / plug) and the
// same 30%-warning / 15%-critical thresholds. The one deliberate departure is
// what "critical" looks like — see blinkOpacity below.
//
// No dedicated service, for the same reason Privacy.qml has none: there's no
// owned I/O to deduplicate across outputs. UPower is already a process-wide
// Quickshell singleton and everything here is a pure derivation over it, with
// upower's daemon doing the polling, multi-battery aggregation and
// time-remaining smoothing.
BarModule {
    id: root

    // Real laptop batteries only: UPower.devices also carries line-power
    // supplies and peripheral batteries.
    readonly property var batteries: UPower.devices.values.filter(dev => dev.isLaptopBattery)
    // upower's aggregate across every battery. Health/cycle counts aren't on
    // it, so the tooltip reads those off the first real battery instead.
    readonly property var device: UPower.displayDevice
    readonly property var mainBattery: batteries.length > 0 ? batteries[0] : null

    contentVisible: batteries.length > 0 && device !== null && device.ready

    // Quickshell normalizes percentage to 0..1, unlike upower's own D-Bus
    // property (0..100).
    readonly property int percent: device && device.ready ? Math.min(100, Math.round(device.percentage * 100)) : 0

    // Named `deviceState`, not `state`: `state` is QQuickItem's own string
    // property driving QML's states/transitions system.
    readonly property int deviceState: device && device.ready ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: deviceState === UPowerDeviceState.Charging
    readonly property bool full: deviceState === UPowerDeviceState.FullyCharged
    // waybar's "Plugged": on the adapter but not charging. The steady state
    // on this machine, which stops at the battery's 80% charge-end threshold
    // (UPower reports PendingCharge for that).
    readonly property bool plugged: !charging && !full && !UPower.onBattery

    // waybar's `states` config: thresholds ascending, first one the capacity
    // is <= wins.
    readonly property string level: percent <= 15 ? "critical" : percent <= 30 ? "warning" : ""

    // waybar's `#battery.critical:not(.charging)`: charging out of a critical
    // level isn't an emergency, so it doesn't blink.
    readonly property bool criticalBlink: level === "critical" && !charging

    // ---- icons ----
    // waybar's format-icons array, one per 20% band.
    readonly property var levelIcons: ["󰂎", "󰁼", "󰁿", "󰂁", "󰁹"]
    readonly property string icon: charging ? "󰂄" : plugged ? "󰚥" : levelIcons[Math.min(levelIcons.length - 1, Math.floor(percent / 20))]

    // The Material Design battery/plug glyphs are drawn upright (nub on top);
    // waybar rotates them 90° into the usual horizontal battery, but not the
    // charging bolt, which stands upright there. Reproduced as-is — set this
    // to `true` if you'd rather have all three consistent.
    readonly property bool rotateIcon: !charging

    // ---- time remaining ----
    // Seconds until empty/full, straight off upower, which already smooths the
    // rate. 0 when it can't tell yet, e.g. just after plugging in.
    readonly property real secondsRemaining: {
        if (!device || !device.ready)
            return 0;
        if (charging)
            return device.timeToFull;
        if (deviceState === UPowerDeviceState.Discharging || deviceState === UPowerDeviceState.PendingDischarge)
            return device.timeToEmpty;
        return 0;
    }

    // waybar's format: "{H} h {M} min", both parts always shown, empty when it
    // rounds down to nothing.
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

    // The estimate when there is one, the plain status when there isn't.
    readonly property string estimateText: {
        const formatted = root.formatDuration(root.secondsRemaining);
        if (formatted === "")
            return root.statusText;
        return (root.charging ? "Full in " : "Empty in ") + formatted;
    }

    // Draw rate and health on a second tooltip line. Health comes off the
    // battery itself: the aggregate display device has no energy-full-design.
    readonly property string detailText: {
        const parts = [];
        if (device && device.ready && Math.abs(device.changeRate) >= 0.05)
            parts.push(Math.abs(device.changeRate).toFixed(1) + " W");
        if (mainBattery && mainBattery.ready && mainBattery.healthSupported && mainBattery.healthPercentage > 0)
            parts.push("Health " + Math.round(mainBattery.healthPercentage) + "%");
        return parts.join("  ·  ");
    }

    contentWidth: content.implicitWidth

    // Icon vertical nudge / size bias — see Mpd.qml. The rotated glyph needs
    // a different nudge from the upright bolt.
    readonly property real iconVerticalOffset: rotateIcon ? 0 : 1
    readonly property real iconSizeRatio: 1.0

    // Deliberately not waybar's critical style (whole module background red,
    // blinking to white twice a second): a solid block of colour fights the
    // pill-shaped groups, and that rate distracts more than it warns. Same
    // signal, quieter — the label and icon turn red and pulse slowly.
    //
    // The pulse bottoms out at 0.6, not near-invisible: opacity fades toward
    // the background, so a deeper trough costs exactly the contrast the
    // warning needs (Theme.critical is 4.4:1 on groupBg at full opacity,
    // 1.6:1 at 0.3). The label also goes bold, which carries more of the
    // signal than the fade does.
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

    // The animation stops mid-pulse when the state clears, leaving
    // blinkOpacity wherever it was — and nothing else drives it back up.
    onCriticalBlinkChanged: {
        if (!criticalBlink)
            blinkOpacity = 1;
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6
        // Whole row, not per-Text: the percentage and icon must pulse together
        // or they read as two separate blinking things.
        opacity: root.blinkOpacity

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            // Bold on the label only: the Nerd Font fallback has no bold face,
            // so Qt would synthesize a smeared one. `font.weight`, not
            // `font.bold` — Inter is variable and Qt picks its axis by number.
            font.weight: root.criticalBlink ? Font.Bold : Font.Normal
            color: root.textColor
            text: root.percent + "%"
        }

        // `rotation` doesn't affect implicit size, so the glyph needs a
        // wrapper to reserve the space its rotated form occupies — otherwise
        // the Row lays it out at the upright width and neighbours overlap it.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            // The tight (ink) bounding rect when rotated, not the swapped
            // implicit sizes: those are the layout box, whose line height runs
            // ~5px past these glyphs' ink and left a visibly wider label/icon
            // gap than every other module's 6px. The ink rect is vertically
            // centered in the line box for this font, so rotating about the
            // wrapper's center needs no further correction.
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

    // Hover tracked by hand rather than via HoverPopupArea: that type drives
    // HoverPopup's show()/requestHide() API, and Tooltip is the other kind of
    // popup (declarative `show`, no grace period). Same wiring as Tray.qml.
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
    }

    // LazyLoader, not Loader: Tooltip is a PopupWindow, not an Item — see
    // Clock.qml's popupLoader.
    LazyLoader {
        active: hover.containsMouse && root.contentVisible

        Tooltip {
            anchorItem: root
            show: hover.containsMouse && root.contentVisible
            text: root.detailText === "" ? root.estimateText : root.estimateText + "<br><br>" + root.detailText
        }
    }
}
