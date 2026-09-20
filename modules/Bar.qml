pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.shared
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
    exclusionMode: ExclusionMode.Auto
    color: Theme.barBg

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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
