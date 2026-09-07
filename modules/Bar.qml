pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.shared
import qs.modules

// One bar instance per output. Which modules appear where is decided by
// shell.qml and passed in as `layout`; this file only knows how to render
// whatever {left, center, right} list of module names it's handed.
PanelWindow {
    id: barWindow

    required property var modelData
    required property var layout
    screen: barWindow.modelData

    // Name -> Component for everything shell.qml's layouts can place.
    // Workspaces needs this bar's screen name (workspace filtering) and
    // NotificationCenter its screen object (routing the shared panel to the
    // clicked screen), so those are bound here rather than bare references.
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

    // Layout entries are plain strings, so a typo would otherwise just render
    // nothing via the Loader.
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
    // Tray/Privacy/Weather are the expensive modules (icon textures, hover
    // popups, network), so they're only instantiated on screens whose layout
    // actually lists them.
    Component { id: trayComponent; Tray {} }
    Component { id: privacyComponent; Privacy {} }
    Component { id: weatherComponent; Weather {} }

    anchors {
        top: true
        left: true
        right: true
    }
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

    // The content area above the border stripe (which is extra height below
    // it, not an overlay).
    Item {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Theme.barHeight

        // No outer margin on the left: the first module's own glyph bearing
        // already lands its ink at the right spot. True for the default order
        // (mpd, submap) — reorder with care.
        ModuleGroup {
            edge: Qt.LeftEdge
            model: barWindow.layout.left
            resolveComponent: barWindow.componentFor
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 10

            Repeater {
                model: barWindow.layout.center
                delegate: ModuleLoader { resolveComponent: barWindow.componentFor }
            }
        }

        // The right group does need an outer margin: a module ending in a
        // digit or flush glyph (e.g. Clock) has near-zero right bearing.
        ModuleGroup {
            edge: Qt.RightEdge
            model: barWindow.layout.right
            resolveComponent: barWindow.componentFor
            outerMargin: Theme.moduleOuterMargin
        }
    }
}
