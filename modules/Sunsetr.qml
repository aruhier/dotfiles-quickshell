pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.shared
import qs.shared.popup
import qs.themes

// Sunsetr indicator and toggle, a thin view over SunsetrService: the glyph
// follows the period, a click starts or stops the daemon, a right click opens
// a menu to toggle or suspend it, and the tooltip carries the period,
// temperature, next change and location.
BarModule {
    id: root

    readonly property bool running: SunsetrService.running
    readonly property string period: SunsetrService.period

    contentVisible: SunsetrService.installed

    // Filled while the filter warms the screen; a faded outline while it
    // leaves it neutral: by day, stopped, or before the first state lands (a
    // connect by day would flash the filled bulb). Lightbulbs rather than the
    // sun and moon the weather module already uses.
    readonly property bool warm: root.running && root.period !== "" && root.period !== "day"
    readonly property string warmIcon: String.fromCodePoint(0xf0335)
    readonly property string neutralIcon: String.fromCodePoint(0xf0336)

    function capitalize(text) {
        return text === "" ? "" : text[0].toUpperCase() + text.slice(1);
    }

    function gammaText(gamma) {
        return Math.round(gamma) === 100 ? "" : "  ·  gamma " + Math.round(gamma) + "%";
    }

    function timeText(date) {
        return Qt.formatTime(date, "hh:mm");
    }

    readonly property string stateText: {
        if (SunsetrService.suspended)
            return "Suspended until " + root.timeText(SunsetrService.resumeAt);
        if (!root.running)
            return "Disabled";
        if (root.period === "")
            return "Connecting…";
        const name = root.capitalize(root.period);
        if (SunsetrService.transitioning)
            return name + " " + Math.round(SunsetrService.progress * 100) + "%  ·  "
                + SunsetrService.temperature + " K → " + SunsetrService.targetTemperature + " K"
                + root.gammaText(SunsetrService.gamma);
        return name + "  ·  " + SunsetrService.temperature + " K" + root.gammaText(SunsetrService.gamma);
    }

    readonly property string detailText: {
        if (!root.running || root.period === "")
            return "";
        const lines = [];
        const next = SunsetrService.nextPeriod;
        if (next && SunsetrService.nextPeriodName !== "")
            lines.push(root.capitalize(SunsetrService.nextPeriodName) + " at " + root.timeText(next));
        if (SunsetrService.preset !== "default")
            lines.push("Preset: " + SunsetrService.preset);
        if (SunsetrService.mode === "geo" && !isNaN(SunsetrService.latitude) && !isNaN(SunsetrService.longitude))
            lines.push("Location: " + SunsetrService.latitude + ", " + SunsetrService.longitude);
        return lines.join("\n");
    }

    // Ink-sized: the bulb is narrow in its cell.
    contentWidth: glyph.implicitWidth

    // Icon vertical nudge / size bias — see Icon.qml.
    readonly property real iconVerticalOffset: 0.8
    readonly property real iconSizeRatio: 0.9

    InkIcon {
        id: glyph
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.iconVerticalOffset
        sizeRatio: root.iconSizeRatio
        // Dimmed the way do-not-disturb is.
        color: root.warm ? root.textColor : Theme.text
        text: root.warm ? root.warmIcon : root.neutralIcon
    }

    // Asked for by a right click. The menu then behaves as a hover popup does
    // while the cursor is on the module or on it, and folds once it leaves
    // both. No click-outside grab: HyprlandFocusGrab cuts all pointer input
    // to the popup itself (notes/quickshell-quirks.md).
    property bool menuOpen: false

    function openMenu() {
        menuLoader.active = true;
        root.menuOpen = true;
    }

    // At once, not after the hover grace: the click is the feedback.
    function closeMenu() {
        root.menuOpen = false;
        const menu = menuLoader.item as HoverPopup;
        if (menu)
            menu.close();
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (root.menuOpen)
                    root.closeMenu();
                else
                    root.openMenu();
            } else {
                root.closeMenu();
                SunsetrService.toggle();
            }
        }
    }

    TooltipLoader {
        show: hover.containsMouse && root.contentVisible && !root.menuOpen
        anchorItem: root
        text: root.detailText === "" ? root.stateText : root.stateText + "\n\n" + root.detailText
    }

    // LazyLoader, not Loader — see HoverPopupArea.qml.
    LazyLoader {
        id: menuLoader
        active: false

        HoverPopup {
            id: menu
            anchorItem: root
            anchorHovered: root.menuOpen && hover.containsMouse
            wantedWidth: 180
            wantedHeight: body.implicitHeight + 2 * padding
            // Menu rows carry their own inset; see MenuRow.qml.
            padding: 4

            // Acts before closing: close() tears the popup down, rows and
            // all, and the action may read from one.
            function pick(action) {
                action();
                root.closeMenu();
            }

            // Folded, closed by a pick, or taken over by another popup.
            onDismissed: {
                root.menuOpen = false;
                menuLoader.active = false;
            }

            ColumnLayout {
                id: body
                anchors.fill: parent
                spacing: 0

                MenuRow {
                    text: "Enabled"
                    value: root.running ? "On" : SunsetrService.suspended ? "Back " + root.timeText(SunsetrService.resumeAt) : "Off"
                    valueColor: root.running ? Theme.accent : Theme.text
                    onActivated: menu.pick(() => SunsetrService.toggle())
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    color: Theme.groupBg
                }

                // A heading, so tighter than a 28px row; inset as a row's label.
                StyledText {
                    Layout.preferredHeight: 24
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                    text: "Suspend for"
                    color: Theme.text
                }

                Repeater {
                    model: [
                        { label: "30 minutes", minutes: 30 },
                        { label: "1 hour", minutes: 60 },
                        { label: "2 hours", minutes: 120 },
                        { label: "4 hours", minutes: 240 },
                        { label: "8 hours", minutes: 480 }
                    ]

                    MenuRow {
                        required property var modelData
                        indent: 10
                        text: modelData.label
                        onActivated: menu.pick(() => SunsetrService.suspend(modelData.minutes))
                    }
                }
            }
        }
    }
}
