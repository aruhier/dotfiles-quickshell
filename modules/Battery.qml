pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.shared
import qs.shared.popup
import qs.themes

// Battery indicator: capacity plus a level icon, a bolt while charging, a
// plug while held on the adapter. Warns at 30%, goes critical at 15% (see
// blinkOpacity). No dedicated service — UPower is already a process-wide
// singleton doing the polling, and everything here derives from it.
BarModule {
    id: root

    // UPower.devices also carries line-power and peripheral batteries.
    readonly property var batteries: UPower.devices.values.filter(dev => dev.isLaptopBattery)
    // upower's aggregate; health/cycle counts are only on a real battery.
    readonly property var device: UPower.displayDevice
    readonly property var mainBattery: batteries.length > 0 ? batteries[0] : null

    contentVisible: batteries.length > 0 && device !== null && device.ready

    // Quickshell normalizes percentage to 0..1, unlike upower's D-Bus 0..100.
    readonly property int percent: device && device.ready ? Math.min(100, Math.round(device.percentage * 100)) : 0

    // Not `state` — that's QQuickItem's own states/transitions property.
    readonly property int deviceState: device && device.ready ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: deviceState === UPowerDeviceState.Charging
    readonly property bool full: deviceState === UPowerDeviceState.FullyCharged
    // On the adapter but not charging — the steady state at this machine's
    // 80% charge-end threshold. Read off the battery's own PendingCharge, not
    // `!UPower.onBattery`: the daemon reports OnBattery false here even while
    // discharging, which showed the plug icon on battery power.
    readonly property bool plugged: deviceState === UPowerDeviceState.PendingCharge

    // Ascending thresholds, first match wins.
    readonly property string level: percent <= 15 ? "critical" : percent <= 30 ? "warning" : ""

    // Charging out of a critical level isn't an emergency, so it won't blink.
    // Gated on contentVisible as well: with no battery present UPower's
    // display device reports 0%, which reads as "critical" and left the blink
    // below running forever behind a hidden module. A running animation keeps
    // every window in the process rendering every frame — see AGENTS.md.
    readonly property bool criticalBlink: contentVisible && level === "critical" && !charging

    // ---- icons ----
    // One per 20% band.
    readonly property var levelIcons: ["󰂎", "󰁼", "󰁿", "󰂁", "󰁹"]
    readonly property string icon: charging ? "󰂄" : plugged ? "󰚥" : levelIcons[Math.min(levelIcons.length - 1, Math.floor(percent / 20))]

    // The battery glyphs are drawn upright (nub on top), so they're rotated
    // into the usual horizontal battery; the charging bolt stands upright as
    // drawn. Set to `true` if you'd rather have all three consistent.
    readonly property bool rotateIcon: !charging

    // ---- time remaining ----
    // Straight off upower, which smooths the rate. 0 when it can't tell yet.
    readonly property real secondsRemaining: {
        if (!device || !device.ready)
            return 0;
        if (charging)
            return device.timeToFull;
        if (deviceState === UPowerDeviceState.Discharging || deviceState === UPowerDeviceState.PendingDischarge)
            return device.timeToEmpty;
        return 0;
    }

    // "{H} h {M} min"; empty when it rounds down to nothing.
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

    // Second tooltip line. Health comes off the battery itself — the
    // aggregate display device has no energy-full-design.
    readonly property string detailText: {
        const parts = [];
        if (device && device.ready && Math.abs(device.changeRate) >= 0.05)
            parts.push(Math.abs(device.changeRate).toFixed(1) + " W");
        if (mainBattery && mainBattery.ready && mainBattery.healthSupported && mainBattery.healthPercentage > 0)
            parts.push("Health " + Math.round(mainBattery.healthPercentage) + "%");
        return parts.join("  ·  ");
    }

    contentWidth: content.implicitWidth

    // Icon nudge/size bias — see Mpd.qml. Rotated and upright differ.
    readonly property real iconVerticalOffset: rotateIcon ? 0 : 1
    readonly property real iconSizeRatio: 1.0

    // The critical warning is a slow pulse on the text, not a red module
    // background: a solid block of colour fights the pill-shaped groups, and a
    // fast blink distracts more than it warns. The trough stops at 0.6 because
    // fading eats contrast (Theme.critical is 4.4:1 on groupBg, 1.6:1 at 0.3);
    // the bold label carries more of the signal than the fade does.
    property real blinkOpacity: 1
    readonly property color labelColor: criticalBlink ? Theme.critical : root.textColor

    SequentialAnimation {
        id: pulse
        // Bounded, and never left on: a running animation keeps every window
        // in the process re-rendering every frame, measured at 3.7% of a core
        // across this machine's three outputs. Slowing the fade down does not
        // help — a 5x longer cycle measured identically — so the lever is how
        // long it runs, not how fast. Three cycles is ~7s, long enough to pull
        // the eye; the red text below carries the warning after that. See
        // AGENTS.md.
        loops: 3

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

    // The percentage the last pulse fired at. What makes the re-pulse below
    // "another whole percent lost" rather than "percent changed": UPower's
    // reading wobbles a point either way near the end, and firing on the way
    // back up would leave the animation running more or less permanently,
    // which is the whole thing this is shaped to avoid. 101 is "none yet".
    property int pulsedAt: 101

    function firePulse() {
        root.pulsedAt = root.percent;
        pulse.restart();
    }

    // Driven from here rather than a `running:` binding, since restart() on a
    // bound `running` would break the binding on the first call.
    onCriticalBlinkChanged: {
        if (root.criticalBlink) {
            root.firePulse();
        } else {
            // The animation can stop mid-pulse, and nothing else resets this.
            pulse.stop();
            root.blinkOpacity = 1;
            root.pulsedAt = 101;
        }
    }

    onPercentChanged: if (root.criticalBlink && root.percent < root.pulsedAt)
        root.firePulse()

    // A reload with the battery already critical evaluates the binding during
    // creation, which can beat the handler above being connected.
    Component.onCompleted: if (root.criticalBlink)
        root.firePulse()

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6
        // Whole row: percentage and icon must pulse together.
        opacity: root.blinkOpacity

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            // Label only: the Nerd Font fallback has no bold face and Qt
            // would smear a synthetic one. See StyledText.qml for `bold`.
            bold: root.criticalBlink
            color: root.labelColor
            text: root.percent + "%"
        }

        // `rotation` doesn't affect implicit size, so this wrapper reserves
        // the rotated glyph's space; otherwise neighbours overlap it.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            // The ink rect, not the swapped implicit sizes: the layout box's
            // line height runs ~5px past these glyphs, widening the label/icon
            // gap. The ink is centered in the line box, so rotating about the
            // wrapper's center needs no correction.
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
                color: root.labelColor
                text: root.icon
            }
        }
    }

    // Hand-rolled hover, not HoverPopupArea: that drives HoverPopup's
    // `anchorHovered`, and Tooltip is the declarative kind. Same as Tray.qml.
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
