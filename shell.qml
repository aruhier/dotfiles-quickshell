import Quickshell
import "modules"

// Quickshell replacement for ~/.config/waybar — one Bar per output,
// following the same per-monitor layout as ~/.config/waybar/config.
ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {}
    }
}
