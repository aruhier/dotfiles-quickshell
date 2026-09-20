pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.themes

// Palette, type and shared geometry for the notification popups and control
// center. Kept separate from Theme.qml — these are their own surfaces, with
// bgSelected below as the one deliberate tie back to the bar.
//
// A value that only one file reads — a gesture's distances, a widget's own
// sizes, the toast lifetimes — lives in that file, not here.
QtObject {
    // Real alpha, so Hyprland's blur layerrule has something to show through.
    // Cards sit lighter than the panel so they still read as chips on it.
    readonly property color bg: Qt.rgba(0.20, 0.20, 0.20, 0.825)
    // Every free-floating surface — the toasts and the OSD pill — takes this
    // one, so the two read as the same pane of glass. Both namespaces carry a
    // Hyprland `blur` layerrule; without one this alpha reads as flat grime
    // rather than as glass. Higher than the panel's: these land over whatever
    // happens to be on screen, and over a white window the blurred bleed is
    // what costs the text its contrast. See notes/notifications.md.
    readonly property color bgFloating: Qt.rgba(0.165, 0.165, 0.165, 0.94)
    readonly property color bgGlobal: Qt.rgba(0.165, 0.165, 0.165, 0.875)
    readonly property color bgHover: "#4b4b4b"
    // Action-button chip fill: above the card, below its hover state.
    readonly property color bgButton: "#404040"
    // A tint applied *over* whichever surface it sits on, rather than an
    // absolute colour. Every plate here is translucent, so its rendered
    // luminance follows the window behind it — a fixed grey holds its contrast
    // over a dark backdrop and loses it over a bright one. Measurements:
    // notes/osd.md. 0.10 reproduces bgButton's appearance on the dark case.
    readonly property color bgOverlay: Qt.rgba(1, 1, 1, 0.10)
    // The bar's accent, so the selection belongs to the same shell.
    readonly property color bgSelected: Theme.accent
    readonly property color borderColor: "#070707"
    readonly property color borderNotification: Qt.rgba(80 / 255, 80 / 255, 80 / 255, 1)
    readonly property color text: "#f5edec"
    readonly property color textDisabled: Qt.rgba(245 / 255, 237 / 255, 236 / 255, 0.5)
    // Hairline outline on cards, peeking group layers and the panel: the text
    // colour at 10%, so it reads as an edge rather than a drawn line.
    readonly property color borderSubtle: Qt.rgba(text.r, text.g, text.b, 0.1)

    readonly property int cardRadius: 10
    // A toast is a floating plate rather than a chip in a list, so it carries
    // more corner than a control-centre card does — closer to the OSD pill it
    // shares a palette with, without going stadium: a toast is tall enough
    // that a stadium would bow its sides.
    readonly property int popupRadius: 18
    readonly property int controlCenterRadius: 12

    // How far a staged gesture bumps, in px — the one distance every floating
    // surface shares: the OSD pill's wind-up before it drops, the control
    // centre's run past its resting place as it arrives, and a control-centre
    // row's wind-up before it leaves. Each site keeps its own note on why the
    // number suits it; a toast's wind-up is not this, see
    // NotificationPopupWindow.qml.
    readonly property int bump: 18

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

    // Their own knobs, not Theme.fontSize (12) — these surfaces are read at
    // arm's length, the bar at a glance. `fontSize` is the base: summary, time
    // and the DND label.
    readonly property int fontSize: 16
    // One step below the summary — what gives a card its title/detail split.
    // Action-button chips take it too.
    readonly property int fontSizeBody: 15
    readonly property int fontSizeTitle: 21

    readonly property int controlCenterWidth: 500
    // Popup stack width: narrow for an ordinary toast, growing only when the
    // content needs it (see NotificationCard.qml's naturalWidth).
    // NotificationPopupWindow.qml clamps to this range. Don't derive it from
    // the control center's width — that leaves too little headroom for the
    // growth to be visible.
    readonly property int popupMinWidth: 380
    readonly property int popupMaxWidth: 500

    // Fixed, not derived from fontSize: this widget's sizing already reads
    // right and shouldn't drift when fontSize changes.
    readonly property int mprisTitleFontSize: 18
    readonly property int mprisArtistFontSize: 15
    readonly property int mprisControlIconSize: 26

}
