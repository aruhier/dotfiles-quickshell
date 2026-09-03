pragma Singleton
import QtQuick

// Palette + metrics for the notification popups/control-center, pulled 1:1
// from the swaync setup this subsystem replaces
// (~/dotfiles/swaync/{style.css,config.json}) so the visual identity carries
// over. Deliberately separate from ../Theme.qml: the bar's teal identity and
// swaync's dark/blue identity are two different visual languages by design —
// Theme.qml "wins on any doubt" only applies to the bar itself.
QtObject {
    readonly property color bg: "#2a2a2a"
    readonly property color bgFloating: Qt.rgba(0.165, 0.165, 0.165, 0.965)
    readonly property color bgGlobal: Qt.rgba(0.165, 0.165, 0.165, 0.95)
    readonly property color bgHover: "#4b4b4b"
    readonly property color bgSelected: "#0080ff"
    readonly property color borderColor: "#070707"
    readonly property color borderNotification: Qt.rgba(80 / 255, 80 / 255, 80 / 255, 1)
    readonly property color text: "#f5edec"
    readonly property color textDisabled: Qt.rgba(245 / 255, 237 / 255, 236 / 255, 0.5)

    readonly property int cardRadius: 10
    readonly property int controlCenterRadius: 12

    // Deliberately larger than Theme.fontSize (12) — this subsystem's own
    // knob, not shared with the bar.
    readonly property int fontSize: 14

    // config.json's notification-window-width.
    readonly property int notificationWidth: 500
    // control-center-width — not set explicitly in config.json, so swaync
    // falls back to configSchema.json's own default (500), not a guess.
    readonly property int controlCenterWidth: 500
    // config.json's control-center-margin-top/bottom.
    readonly property int controlCenterMarginV: 50

    // config.json's mpris widget-config. Sized up well past the base
    // fontSize/iconFontSize — the now-playing widget is meant to read as a
    // hero element in the panel, not blend in with the notification list.
    readonly property int mprisImageSize: 96
    readonly property int mprisImageRadius: 16
    readonly property int mprisTitleFontSize: fontSize + 4
    readonly property int mprisArtistFontSize: fontSize + 1
    readonly property int mprisControlIconSize: 26

    // config.json's timeout/timeout-low/timeout-critical (seconds -> ms).
    // Critical's 0 means "no auto-dismiss".
    readonly property int timeoutLow: 5000
    readonly property int timeoutNormal: 10000
    readonly property int timeoutCritical: 0
}
