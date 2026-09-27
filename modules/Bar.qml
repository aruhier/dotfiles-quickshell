pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.shared
import qs.shared.animations
import qs.shared.popup
import qs.modules
import qs.themes

// One bar instance per output. Which modules appear where is decided by
// shell.qml and passed in as `layout`; this file only knows how to render
// whatever {left, center, right} it's handed: a list of module groups for
// each edge, a list of module names for the center.
PanelWindow {
    id: barWindow

    required property var modelData
    required property var layout
    screen: barWindow.modelData

    // Auto-hide, configured and driven from shell.qml. `hideOn` is its
    // `barHideOn`; both override maps are set over IPC. See notes/autohide.md.
    required property var hideOn
    required property var outputOverrides
    required property var workspaceOverrides
    required property int hideDelay

    // Opening a special workspace leaves this alone: Hyprland reports those
    // separately, and Quickshell doesn't fold them in.
    readonly property HyprlandWorkspace workspace: Hyprland.monitorFor(barWindow.modelData)?.activeWorkspace ?? null

    // A number is a workspace id, a string a name.
    function matchesWorkspace(entries, ws) {
        return (entries ?? []).some(e => typeof e === "number" ? e === ws.id : e === ws.name);
    }

    // Exactly one tiled window here. A tab group counts once, by its first
    // member: inactive tabs aren't `hidden`. A window whose state isn't fetched
    // yet isn't counted: a floating dialog would otherwise bring the bar back
    // until shell.qml's refresh lands.
    readonly property bool singleTiled: barWindow.workspace !== null && barWindow.workspace.toplevels.values.filter(t => barWindow.countsAsTile(t.lastIpcObject)).length === 1
    function countsAsTile(ipc) {
        return ipc.floating === false && !ipc.hidden && (!ipc.grouped?.length || ipc.grouped[0] === ipc.address);
    }

    // The three levels, each falling back to the one before; the IPC's
    // `toggle` reads them to decide whether to clear an override or set one.
    readonly property bool hiddenByRule: barWindow.singleTiled && (barWindow.matchesWorkspace(barWindow.hideOn["*"], barWindow.workspace) || barWindow.matchesWorkspace(barWindow.hideOn[barWindow.modelData.name], barWindow.workspace))
    readonly property bool hiddenForWorkspace: (barWindow.workspace !== null && barWindow.workspace.name in barWindow.workspaceOverrides) ? barWindow.workspaceOverrides[barWindow.workspace.name] : barWindow.hiddenByRule
    // null follows the workspace; true/false forces every workspace here.
    readonly property var outputOverride: barWindow.modelData.name in barWindow.outputOverrides ? barWindow.outputOverrides[barWindow.modelData.name] : null
    readonly property bool shouldHide: barWindow.outputOverride !== null ? barWindow.outputOverride : barWindow.hiddenForWorkspace

    // `shouldHide`, late by `hideDelay` on the way to hidden: a workspace only
    // passed through never gives up the bar's space, so windows don't resize
    // twice. Showing is immediate — the switch was made to see it.
    property bool hiddenAfterDelay: false
    onShouldHideChanged: {
        if (barWindow.shouldHide) {
            hideDelayTimer.restart();
        } else {
            hideDelayTimer.stop();
            barWindow.hiddenAfterDelay = false;
        }
    }
    // For an IPC call, which asked for the change now.
    function skipDelay() {
        hideDelayTimer.stop();
        barWindow.hiddenAfterDelay = barWindow.shouldHide;
    }
    Timer {
        id: hideDelayTimer
        interval: barWindow.hideDelay
        // Never out from under the cursor, or from under anything it opened.
        onTriggered: {
            if (barWindow.peekHeld)
                restart();
            else
                barWindow.hiddenAfterDelay = barWindow.shouldHide;
        }
    }

    // Hyprland's state arrives after the bar is built on a cold start, so the
    // first workspace is applied as is: loading on a hide-listed workspace
    // must not show the bar for a delay and then resize every window.
    property bool workspaceKnown: false
    onWorkspaceChanged: barWindow.settleFirstWorkspace()
    Component.onCompleted: barWindow.settleFirstWorkspace()
    function settleFirstWorkspace() {
        if (barWindow.workspaceKnown || barWindow.workspace === null)
            return;
        barWindow.workspaceKnown = true;
        barWindow.skipDelay();
        if (barWindow.hiddenAfterDelay) {
            slide.snapTo(-barWindow.implicitHeight);
            barWindow.reservesSpace = false;
        }
    }

    // The notification panel belongs to the bar, so it brings the bar with it
    // — as a peek, so opening it never resizes windows.
    readonly property bool panelOpenHere: NotificationService.centerOpen && NotificationService.centerScreen === barWindow.modelData

    // Pulled in over the windows while hidden: by the cursor resting on the
    // top edge (latched until the grace timer lets go) or by the panel.
    property bool peekLatched: false
    readonly property bool peeking: barWindow.hiddenAfterDelay && (barWindow.peekLatched || barWindow.panelOpenHere)
    // The panel closing hands its peek to the grace timer, so the bar doesn't
    // vanish from under a cursor already on it.
    onPanelOpenHereChanged: if (!barWindow.panelOpenHere && barWindow.hiddenAfterDelay)
        barWindow.peekLatched = true
    onPeekLatchedChanged: if (barWindow.peekLatched && !barWindow.peekHeld)
        peekGraceTimer.restart()

    // Anything of this bar's that the cursor can be on instead of the bar.
    readonly property bool peekHeld: surfaceHover.hovered || barWindow.panelOpenHere || barWindow.anchoredHere(PopupCoordinator.activeOwner?.anchorItem) || barWindow.anchoredHere(PopupCoordinator.trayMenuOwner)
    function anchoredHere(item) {
        return (item?.QsWindow.window ?? null) === barWindow;
    }
    onPeekHeldChanged: {
        if (barWindow.peekHeld)
            peekGraceTimer.stop();
        else if (barWindow.peekLatched)
            peekGraceTimer.restart();
    }
    // A larger target than a hover popup, so a longer grace than its 200ms.
    Timer {
        id: peekGraceTimer
        interval: 400
        onTriggered: if (!barWindow.peekHeld)
            barWindow.peekLatched = false
    }

    // Out of sight above the top edge: hidden and not peeking.
    readonly property bool retracted: barWindow.hiddenAfterDelay && !barWindow.peeking
    onHiddenAfterDelayChanged: if (!barWindow.hiddenAfterDelay) {
        barWindow.peekLatched = false;
        barWindow.reservesSpace = true;
    }

    // Every change is the same gesture: the bar lives just above the top edge
    // and slides down out of it, for a rule, an IPC call or a peek alike.
    // Critically damped, ~170ms. No overshoot either way: the bar is flush
    // with the screen edge, and a bump would open a sliver of gap above it.
    FrameSpring {
        id: slide
        to: barWindow.retracted ? -barWindow.implicitHeight : 0
        stiffness: 900
        damping: 46.5
    }

    // The spring lands exactly on its target.
    readonly property bool fullyRetracted: slide.value <= -barWindow.implicitHeight
    // Space is given up only once the bar is out of sight, so windows grow
    // into an empty strip instead of under a moving bar. Reserved again the
    // moment it shows, so windows move down with it.
    property bool reservesSpace: true
    onFullyRetractedChanged: if (barWindow.fullyRetracted && barWindow.retracted)
        barWindow.reservesSpace = false

    // With the space given up over a lone tiled window, that window takes
    // the whole screen, in the same resize.
    EdgeRelease {
        output: barWindow.modelData.name
        workspaceName: !barWindow.reservesSpace && barWindow.singleTiled ? barWindow.workspace.name : ""
    }

    // Name -> Component for everything shell.qml's layouts can place. Two of
    // them need this bar's screen, so they're bound rather than bare.
    readonly property var moduleComponents: ({
        mpd: mpdComponent,
        submap: submapComponent,
        workspaces: workspacesComponent,
        backlight: backlightComponent,
        battery: batteryComponent,
        volume: volumeComponent,
        notifications: notificationsComponent,
        clock: clockComponent,
        tray: trayComponent,
        privacy: privacyComponent,
        weather: weatherComponent
    })

    // Layout entries are plain strings, so a typo would silently render
    // nothing.
    function componentFor(name) {
        const component = barWindow.moduleComponents[name];
        if (!component)
            console.warn("Bar: unknown module \"" + name + "\" in layout — check moduleComponents");
        return component;
    }

    Component { id: mpdComponent; Mpd {} }
    Component { id: submapComponent; Submap {} }
    Component { id: workspacesComponent; Workspaces { screenName: barWindow.modelData.name } }
    Component { id: backlightComponent; Backlight {} }
    Component { id: batteryComponent; Battery {} }
    Component { id: volumeComponent; Volume {} }
    Component { id: notificationsComponent; NotificationCenter { screen: barWindow.modelData } }
    Component { id: clockComponent; Clock {} }
    // The expensive modules — icon textures, hover popups, network. Only
    // instantiated on screens whose layout lists them.
    Component { id: trayComponent; Tray {} }
    Component { id: privacyComponent; Privacy {} }
    Component { id: weatherComponent; Weather {} }

    anchors {
        top: true
        left: true
        right: true
    }
    // Not the window's height — layer-shell adds the reverse-edge margin to
    // the exclusive zone, so this is 1px of reserved gap under the border
    // stripe (windows tile at 26 + gaps_out, the surface is 25 tall).
    margins.bottom: 1
    implicitHeight: Theme.barHeight + Theme.barBorderHeight
    exclusionMode: barWindow.reservesSpace ? ExclusionMode.Auto : ExclusionMode.Ignore
    // The surface stays mapped while hidden, so its paint is `content`'s.
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Hidden, only the top row takes input and everything under it gets its
    // clicks. That row sits in the gap above tiled windows.
    mask: barWindow.retracted ? peekTriggerRegion : null
    readonly property Region peekTriggerRegion: Region {
        item: peekTrigger
    }

    // On the window rather than `content`, so it covers the peek trigger too.
    // A HoverHandler keeps hover under the modules' own MouseAreas.
    HoverHandler {
        id: surfaceHover
    }

    // The peek's trigger. It waits for the cursor to rest, and restarts when
    // the cursor runs along the edge: outputs sit side by side, so the top
    // edge is also a path between them.
    MouseArea {
        id: peekTrigger
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        enabled: barWindow.retracted
        hoverEnabled: true

        property real dwellX: 0
        onEntered: {
            dwellX = mouseX;
            peekDwellTimer.restart();
        }
        onPositionChanged: {
            if (Math.abs(mouseX - dwellX) > 40) {
                dwellX = mouseX;
                peekDwellTimer.restart();
            }
        }
        onExited: peekDwellTimer.stop()

        // Long enough that a tab grab overshooting to the edge doesn't fire it.
        Timer {
            id: peekDwellTimer
            interval: 250
            onTriggered: barWindow.peekLatched = true
        }
    }

    Item {
        id: content
        width: parent.width
        height: parent.height
        y: Math.round(slide.value)
        visible: !barWindow.fullyRetracted

        Rectangle {
            anchors.fill: parent
            color: Theme.barBg
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.barBorderHeight
            color: Theme.barBorder
        }

        // Above the border stripe, which is extra height rather than an overlay.
        Item {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Theme.barHeight

            // No outer margin: the first module's glyph bearing already lands its
            // ink in the right place. Depends on the order (mpd first).
            ModuleGroupRow {
                edge: Qt.LeftEdge
                groups: barWindow.layout.left
                resolveComponent: barWindow.componentFor
            }

            ModuleRow {
                anchors.centerIn: parent
                model: barWindow.layout.center
                resolveComponent: barWindow.componentFor
            }

            // This one needs a margin: a module ending in a digit or flush glyph
            // (Clock) has near-zero right bearing.
            ModuleGroupRow {
                edge: Qt.RightEdge
                groups: barWindow.layout.right
                resolveComponent: barWindow.componentFor
                outerMargin: Theme.moduleOuterMargin
            }
        }
    }
}
