pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Palette and metrics for the notification popups and control center. Kept
// separate from ../Theme.qml — these are their own surfaces, with bgSelected
// below as the one deliberate tie back to the bar.
QtObject {
    // Real alpha, so Hyprland's blur layerrule has something to show through.
    // Cards sit lighter than the panel so they still read as chips on it.
    readonly property color bg: Qt.rgba(0.20, 0.20, 0.20, 0.825)
    readonly property color bgFloating: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgGlobal: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgHover: "#4b4b4b"
    // Action-button chip fill: above the card, below its hover state.
    readonly property color bgButton: "#404040"
    // A tint applied *over* whichever surface it sits on, rather than an
    // absolute colour. Every plate here is translucent, so its rendered
    // luminance follows the window behind it — a fixed grey holds its contrast
    // over a dark backdrop and loses it over a bright one. Measurements:
    // AGENTS.md. 0.10 reproduces bgButton's appearance on the dark case.
    readonly property color bgOverlay: Qt.rgba(1, 1, 1, 0.10)
    // Theme.qml's bar accent, so the selection belongs to the same shell.
    readonly property color bgSelected: "#6AA099"
    readonly property color borderColor: "#070707"
    readonly property color borderNotification: Qt.rgba(80 / 255, 80 / 255, 80 / 255, 1)
    readonly property color text: "#f5edec"
    readonly property color textDisabled: Qt.rgba(245 / 255, 237 / 255, 236 / 255, 0.5)
    // Hairline outline on cards, peeking group layers and the panel: the text
    // colour at 10%, so it reads as an edge rather than a drawn line.
    readonly property color borderSubtle: Qt.rgba(text.r, text.g, text.b, 0.1)

    readonly property int cardRadius: 10
    readonly property int controlCenterRadius: 12

    // ---- control-center metrics ----
    // Every widget is inset 16px from the panel edge; adjacent widgets sit a
    // 32px gutter apart.
    readonly property int panelPadding: 16
    readonly property int panelSpacing: 32
    // Extra inset *inside* the list widget, on top of panelPadding: a card's
    // left edge lands 42px from the panel edge, against the labels' 16px.
    // Sizes here are the design intent; the call sites run the ones that move
    // a whole subtree through `Screens.snap()` for the device pixel grid.
    readonly property int listPadding: 26
    // Each row's top and bottom inset, so stacked cards sit twice this apart.
    readonly property int listCardMargin: 14

    // The DND switch: 48x29 with a 20px slider.
    readonly property int switchWidth: 48
    readonly property int switchHeight: 29
    readonly property int switchPadding: 4

    // Their own knobs, not Theme.fontSize (12) — these surfaces are read at
    // arm's length, the bar at a glance. `fontSize` is the base: summary, time
    // and the DND label.
    readonly property int fontSize: 16
    // One step below the summary — what gives a card its title/detail split.
    readonly property int fontSizeBody: 15
    readonly property int fontSizeAction: 15
    readonly property int fontSizeTitle: 21

    readonly property int controlCenterWidth: 500
    // Gap above and below the panel, so it floats rather than filling the edge.
    readonly property int controlCenterMarginV: 50
    // Popup stack width: narrow for an ordinary toast, growing only when the
    // content needs it (see NotificationCard.qml's naturalWidth).
    // NotificationPopupWindow.qml clamps to this range. Don't derive it from
    // the control center's width — that leaves too little headroom for the
    // growth to be visible.
    readonly property int popupMinWidth: 380
    readonly property int popupMaxWidth: 500

    // Album art, sized to carry the widget rather than sit beside the text.
    readonly property int mprisImageSize: 80
    readonly property int mprisImageRadius: 14
    // Fixed, not derived from fontSize: this widget's sizing already reads
    // right and shouldn't drift when fontSize changes.
    readonly property int mprisTitleFontSize: 18
    readonly property int mprisArtistFontSize: 15
    readonly property int mprisControlIconSize: 26

    // Toast lifetimes in ms; critical's 0 means "no auto-dismiss".
    readonly property int timeoutLow: 5000
    readonly property int timeoutNormal: 10000
    readonly property int timeoutCritical: 0
}
