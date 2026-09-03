import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../shared"

// One bar instance per output. Which modules appear where is decided by
// shell.qml (`layout`, passed in) — this file only knows how to render
// whatever {left, center, right} list of module names it's handed.
PanelWindow {
    id: barWindow

    required property var modelData
    required property var layout
    screen: modelData

    // String -> Component lookup for everything shell.qml's layouts can
    // place. Workspaces needs this bar's own screen name (workspace
    // filtering) and NotificationCenter needs this bar's own screen object
    // (routing the shared notification panel to the clicked screen), so
    // their Components are bound here rather than being bare module
    // references.
    readonly property var moduleComponents: ({
        mpd: mpdComponent,
        submap: submapComponent,
        workspaces: workspacesComponent,
        backlight: backlightComponent,
        volume: volumeComponent,
        notifications: notificationsComponent,
        clock: clockComponent,
        tray: trayComponent,
        privacy: privacyComponent,
        weather: weatherComponent
    })

    // Layout arrays are plain strings (see shell.qml), so a typo'd module
    // name would otherwise just silently render nothing via the Loader.
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
    Component { id: volumeComponent; Volume {} }
    Component { id: notificationsComponent; NotificationCenter { screen: barWindow.modelData } }
    Component { id: clockComponent; Clock {} }
    // Tray/Privacy/Weather are the more expensive modules (icon textures,
    // hover popups, network) — they only get instantiated at all when a
    // screen's layout actually lists them, e.g. via shell.qml's
    // `mainScreens`.
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

    // The 22px content area above the border stripe (border is extra
    // height below it, not an overlay).
    Item {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Theme.barHeight

        // ---- left ----
        // Flush against the screen edge, rounded only on the inner side —
        // mirrors .modules-left's one-sided pill. No outer margin here
        // since the first module's own glyph bearing already lands its ink
        // at the right spot (unlike the right group, see below) — true for
        // the default left order (mpd, submap); reorder with care.
        ModuleGroup {
            edge: Qt.LeftEdge
            model: barWindow.layout.left
            resolveComponent: barWindow.componentFor
        }

        // ---- center ----
        RowLayout {
            anchors.centerIn: parent
            spacing: 10

            Repeater {
                model: barWindow.layout.center
                delegate: ModuleLoader { resolveComponent: barWindow.componentFor }
            }
        }

        // ---- right ----
        // Mirror of the left group, but the outer edge needs
        // moduleOuterMargin too: a module ending in a digit/flush glyph
        // (e.g. Clock) has near-zero right bearing, so it needs the
        // explicit margin to keep spacing even.
        ModuleGroup {
            edge: Qt.RightEdge
            model: barWindow.layout.right
            resolveComponent: barWindow.componentFor
            outerMargin: Theme.moduleOuterMargin
        }
    }
}
