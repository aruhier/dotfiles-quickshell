pragma Singleton
import QtQuick

// Palette + metrics for the notification popups/control-center, pulled 1:1
// from the swaync setup this subsystem replaces
// (~/dotfiles/swaync/{style.css,config.json}) so the visual identity carries
// over. Otherwise kept separate from ../Theme.qml — but bgSelected below is
// a deliberate exception, pulled from Theme.qml's bar accent by request to
// tie the two surfaces' selection color together.
QtObject {
    // Panel/card fills carry real alpha (swaync's own values were
    // rgb(42,42,42) / rgba(...,0.95) — opaque enough that Hyprland's
    // `layerrule = blur, quickshell-notification-center` had nothing to
    // show through). Cards sit slightly lighter than the panel so they
    // still read as chips on top of it.
    readonly property color bg: Qt.rgba(0.20, 0.20, 0.20, 0.825)
    readonly property color bgFloating: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgGlobal: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgHover: "#4b4b4b"
    // Action-button chip fill — not in this user's ~/.config/swaync/style.css
    // (which only recolors backgrounds/text, not buttons) nor in swaync's own
    // built-in style.scss (.text-button gets no explicit background there,
    // so it falls through to the GTK theme's default button chrome). Picked
    // to match a live swaync screenshot's actual rendered button color
    // (~/tmp/swaync-screenshot.png, sampled rgb(64,64,64)) rather than guess
    // at the underlying GTK theme.
    readonly property color bgButton: "#404040"
    // Matches Theme.qml's bar accent — ties the notification panel's
    // selection color to the bar's own identity instead of an unrelated blue.
    readonly property color bgSelected: "#6AA099"
    readonly property color borderColor: "#070707"
    readonly property color borderNotification: Qt.rgba(80 / 255, 80 / 255, 80 / 255, 1)
    readonly property color text: "#f5edec"
    readonly property color textDisabled: Qt.rgba(245 / 255, 237 / 255, 236 / 255, 0.5)

    readonly property int cardRadius: 10
    readonly property int controlCenterRadius: 12

    // Deliberately larger than Theme.fontSize (12) — this subsystem's own
    // knob, not shared with the bar. Bumped from the original 1:1-with-swaync
    // 14 by request — read as too small next to a live swaync screenshot at
    // the same card width once compared side by side.
    readonly property int fontSize: 16

    // control-center-width — not set explicitly in config.json, so swaync
    // falls back to configSchema.json's own default (500), not a guess.
    readonly property int controlCenterWidth: 500
    // config.json's control-center-margin-top/bottom.
    readonly property int controlCenterMarginV: 50
    // Popup stack width, by request: narrow (380) for an ordinary toast, but
    // grows up to a control-center card's own width when a toast's content
    // (long summary/time, or wide action-button labels — see
    // NotificationCard.qml's naturalWidth) actually needs more room, instead
    // of always reserving the wider size. NotificationPopupWindow.qml clamps
    // to this range using the max naturalWidth across currently-shown popups.
    readonly property int notificationMinWidth: 380
    // The control-center list's own left/rightMargin (NotificationCenterPanel
    // .qml's notificationListView) — subtracted so the popup, at its widest,
    // tops out at the same width as a control-center card. Popups have no
    // equivalent side margins of their own (NotificationPopupWindow.qml's
    // Column spans the full window width), so this has to be baked in here
    // instead of just reusing controlCenterWidth directly.
    readonly property int notificationMaxWidth: controlCenterWidth - 24

    // config.json's mpris widget-config is image-size: 64 / image-radius: 12
    // (~/dotfiles/swaync/config.json) — bumped up from that by request, art
    // read as too small at the literal config value once seen live.
    readonly property int mprisImageSize: 80
    readonly property int mprisImageRadius: 14
    // Fixed, not `fontSize + N` — that used to track fontSize's bump above,
    // but the mpris widget's sizing already reads right (per direct
    // request, left untouched), so these are now their own frozen knob
    // instead of drifting every time fontSize changes.
    readonly property int mprisTitleFontSize: 18
    readonly property int mprisArtistFontSize: 15
    readonly property int mprisControlIconSize: 26

    // config.json's timeout/timeout-low/timeout-critical (seconds -> ms).
    // Critical's 0 means "no auto-dismiss".
    readonly property int timeoutLow: 5000
    readonly property int timeoutNormal: 10000
    readonly property int timeoutCritical: 0
}
