pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.shared

// Hyprland submap indicator: an italic label, hidden on the default submap —
// a thin view over SubmapService. The cream pill and the text colour on it
// are the group's, not this module's: shell.qml's layout puts it in its own
// ModuleGroup, which slides away with it.
BarModule {
    id: root

    // A submap name is a mode indicator, not a message.
    readonly property int maxLength: 30

    contentVisible: SubmapService.active
    contentWidth: label.implicitWidth

    StyledText {
        id: label
        anchors.centerIn: parent
        // The last name, still there while the group collapses over it.
        text: SubmapService.lastName.substring(0, root.maxLength)
        font.italic: true
        bold: true
        color: root.textColor
    }
}
