pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Palette and metrics for the notification popups and control center, pulled
// from the swaync setup this subsystem replaces so the visual identity carries
// over. Otherwise kept separate from ../Theme.qml, with bgSelected below as
// the deliberate exception.
QtObject {
    // Panel and card fills carry real alpha: swaync's own values were opaque
    // enough that Hyprland's blur layerrule had nothing to show through. Cards
    // sit slightly lighter than the panel so they still read as chips on it.
    readonly property color bg: Qt.rgba(0.20, 0.20, 0.20, 0.825)
    readonly property color bgFloating: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgGlobal: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgHover: "#4b4b4b"
    // Action-button chip fill. Neither stylesheet sets one — swaync falls
    // through to the GTK theme's default button chrome — so this is sampled
    // from a live swaync screenshot rather than guessed at.
    readonly property color bgButton: "#404040"
    // Matches Theme.qml's bar accent, tying the panel's selection color to
    // the bar's identity instead of an unrelated blue.
    readonly property color bgSelected: "#6AA099"
    readonly property color borderColor: "#070707"
    readonly property color borderNotification: Qt.rgba(80 / 255, 80 / 255, 80 / 255, 1)
    readonly property color text: "#f5edec"
    readonly property color textDisabled: Qt.rgba(245 / 255, 237 / 255, 236 / 255, 0.5)
    // Hairline outline on a card, a peeking group layer and the panel: the
    // text colour at 10%, so it reads as an edge rather than a drawn line.
    readonly property color borderSubtle: Qt.rgba(text.r, text.g, text.b, 0.1)

    readonly property int cardRadius: 10
    readonly property int controlCenterRadius: 12

    // ---- control-center metrics ----
    // From swaync's `.widget { margin: 8px; padding: 8px }`: every widget is
    // inset 8+8 = 16px from the panel edge, and two adjacent widgets' margins
    // stack into a 32px gutter (GTK doesn't collapse margins).
    readonly property int panelPadding: 16
    readonly property int panelSpacing: 32
    // The extra inset a card carries *inside* the list widget, on top of
    // panelPadding: its left edge sits 42px from the panel edge against the
    // labels' 16px. Measured rather than derived — only the sum is
    // observable.
    readonly property int listPadding: 26
    // Each row's own top and bottom inset, so two stacked cards sit twice
    // this apart.
    readonly property int listCardMargin: 14

    // .widget-dnd's GTK switch, measured at 48x29 with a 20px slider.
    readonly property int switchWidth: 48
    readonly property int switchHeight: 29
    readonly property int switchPadding: 4

    // Font sizes, measured off a live swaync screenshot and cross-checked
    // against the CSS swaync actually loads. Deliberately its own set of
    // knobs, not Theme.fontSize (12), which the bar owns.
    //
    // `fontSize` is the base: swaync's --font-size-summary, shared by the
    // summary and the time label, and close enough to the DND label's own
    // size to reuse rather than carry a fourth constant.
    readonly property int fontSize: 16
    // One step below the summary — what gives a card its title/detail split.
    readonly property int fontSizeBody: 15
    // Action-button labels get no font-size rule in either stylesheet, so
    // they render at GTK's root size: 11pt ≈ 14.7px.
    readonly property int fontSizeAction: 15
    // The stylesheet computes to 22px, but Qt renders Inter ~5% larger than
    // Pango at the same nominal pixelSize here, so this is the value that
    // actually matches on screen.
    readonly property int fontSizeTitle: 21

    // swaync's own default control-center-width.
    readonly property int controlCenterWidth: 500
    // swaync's control-center-margin-top/bottom.
    readonly property int controlCenterMarginV: 50
    // Popup stack width: narrow for an ordinary toast, growing up to a
    // control-center card's width when the content needs it (see
    // NotificationCard.qml's naturalWidth) rather than always reserving the
    // wider size. NotificationPopupWindow.qml clamps to this range.
    readonly property int notificationMinWidth: 380
    // A control-center card's total side inset (panelPadding + listPadding)
    // subtracted, so a popup at its widest matches a card exactly. Popups have
    // no side margins of their own, so this has to be baked in rather than
    // reusing controlCenterWidth directly.
    readonly property int notificationMaxWidth: controlCenterWidth - (panelPadding + listPadding) * 2

    // Bumped up from swaync's own 64/12: the art read as too small at the
    // literal config value once seen live.
    readonly property int mprisImageSize: 80
    readonly property int mprisImageRadius: 14
    // Fixed, not derived from fontSize: the mpris widget's sizing already
    // reads right and shouldn't drift when fontSize changes.
    readonly property int mprisTitleFontSize: 18
    readonly property int mprisArtistFontSize: 15
    readonly property int mprisControlIconSize: 26

    // swaync's timeout/timeout-low/timeout-critical, in ms. Critical's 0
    // means "no auto-dismiss".
    readonly property int timeoutLow: 5000
    readonly property int timeoutNormal: 10000
    readonly property int timeoutCritical: 0
}
