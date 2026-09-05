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

    // ---- control-center metrics ----
    // Measured off the same reference screenshot as the font sizes below
    // (~/tmp/swaync-notification-panel.png), and all explained by swaync's `.widget { margin: 8px; padding: 8px }`: every
    // widget in the panel (title, dnd, the notification list, mpris) is
    // inset 8+8 = 16px from the panel's edge, and two adjacent widgets'
    // margins stack into a 32px gutter between them (GTK doesn't collapse
    // margins the way CSS block layout does).
    readonly property int panelPadding: 16
    readonly property int panelSpacing: 32
    // The extra inset a notification card carries *inside* the list widget,
    // on top of panelPadding — the card's left edge measures 42px from the
    // panel edge, against the 16px the title/DND labels sit at. Half of it
    // is `.notification-background { padding: 6px 12px }`, the rest GTK's
    // own list-row chrome; measured rather than derived, since only the sum
    // is observable.
    readonly property int listPadding: 26
    // Vertical half of that same `padding: 6px 12px` as it actually
    // measures (~14px top and bottom of each row), so the gap between two
    // stacked cards is twice this.
    readonly property int listCardMargin: 14

    // .widget-dnd's GTK switch, measured at 48x29 with a 20px slider —
    // noticeably larger than the 40x22 this used to draw.
    readonly property int switchWidth: 48
    readonly property int switchHeight: 29
    readonly property int switchPadding: 4

    // Font sizes, measured off a live swaync control-center screenshot
    // (~/tmp/swaync-notification-panel.png, native 2944x1840 at the
    // compositor's 1.6 scale — so a value here is that shot's glyph height
    // in physical px divided by 1.6) and cross-checked against the CSS the
    // running swaync actually loads: /etc/xdg/swaync/style.css supplies the
    // sizes, since this user's ~/.config/swaync/style.css only recolors.
    // Deliberately its own set of knobs rather than Theme.fontSize (12),
    // which the bar owns.
    //
    // `fontSize` is the base: --font-size-summary (16px), which the summary
    // and the time label share (`.time` sets the same var, both bold).
    // .widget-dnd's own label is 1.1rem off an 11pt root ≈ 16.1px, close
    // enough to reuse this rather than carry a fourth constant.
    readonly property int fontSize: 16
    // --font-size-body (15px) — one step below the summary, which is what
    // gives a card its title/detail split.
    readonly property int fontSizeBody: 15
    // Action-button labels get no font-size rule of their own in either
    // stylesheet, so they render at GTK's root size: 11pt ≈ 14.7px.
    readonly property int fontSizeAction: 15
    // `.widget-title > label { font-size: 1.5rem }` against that same 11pt
    // root works out to 22px, but Qt renders Inter measurably larger than
    // Pango does at the same nominal pixelSize on this 1.6x output (a
    // side-by-side of the two panels put Qt's cap height ~5% over swaync's),
    // so this is the value that actually matches on screen rather than the
    // one the stylesheet computes to.
    readonly property int fontSizeTitle: 21

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
    // Everything a control-center card is inset by on each side — the
    // panel's own panelPadding plus the list's listPadding (see
    // NotificationCenterPanel.qml's ColumnLayout and notificationListView)
    // — subtracted so the popup, at its widest, tops out at exactly the same
    // width as a control-center card. Popups have no equivalent side margins
    // of their own (NotificationPopupWindow.qml's Column spans the full
    // window width), so this has to be baked in here instead of just reusing
    // controlCenterWidth directly.
    readonly property int notificationMaxWidth: controlCenterWidth - (panelPadding + listPadding) * 2

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
