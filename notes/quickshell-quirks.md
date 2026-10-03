# Quickshell quirks

Upstream Quickshell behaviour this repo works around, one entry per quirk,
so a workaround can go when upstream fixes it. Each says the version it was
seen on, how it was established, what works around it (grep for the symbol),
and how to tell it is fixed. The reasoning behind each workaround stays in
its subject note; this file only indexes it.

When upgrading Quickshell, walk this list. Re-test the original failure
before removing anything (see the lesson at the end of `notes/privacy.md`).
Our own QML traps, not upstream's, are in `notes/qml-gotchas.md`.

## Hyprland IPC

- **`refreshToplevels()` never takes a window off its old workspace's
  `toplevels`.** It re-points `t.workspace` and inserts into the new list;
  only the `movewindowv2` handler removes from the old one. A refresh whose
  reply lands before a move's `movewindowv2` leaves the window in both lists
  until it closes or the old workspace is destroyed. `openwindow` for an
  already-known address leaks the same way.
  - Seen: 0.3.1, read in `src/wayland/hyprland/ipc/connection.cpp`
    (`refreshToplevels`, `movewindowv2` handler) and `workspace.cpp`
    (`insertToplevel`). The race itself is inferred, not reproduced. A pinned
    window is *not* a trigger on Hyprland 0.56: it sends `movewindowv2`
    (tested live, 2026-09-29).
  - Workaround: every reader filters `t.workspace === ws`:
    `Workspaces.qml` (`windows`), `WorkspacePreviewPopup.qml` (`shows()`),
    `Bar.qml` (`singleTiledOn`). Detail: `notes/workspaces.md`.
  - Fixed when: `refreshToplevels()` removes the toplevel from the workspace
    it leaves.

- **A refresh asked for while one of the same kind is in flight is dropped,
  not queued**, and nothing signals when one lands.
  - Seen: 0.3.1, `connection.cpp`: each `refreshX` returns early on its
    `requestingX` flag.
  - Workaround: `services/HyprlandRefreshService.qml` coalesces every ask and
    sends each refresh twice. Detail: `notes/autohide.md`.
  - Fixed when: a refresh asked mid-flight is re-run after the current one,
    or a completion signal exists. The service could then call straight
    through, or go.

- **Events don't update `lastIpcObject`.** `floating`, `hidden`, `grouped`
  and window geometry only change on `refreshToplevels()`; monitor
  `x/y/width/height/scale` and `transform` only on `refreshMonitors()`,
  which Quickshell runs itself only on connect, `configreloaded` and
  `monitoraddedv2`.
  - Seen: 0.3.1, observed; the `configreloaded` refresh read in
    `connection.cpp`.
  - Workaround: `shell.qml` refreshes toplevels on the window events in
    `toplevelEvents`; `WorkspacePreviewPopup.qml` refreshes both on open.
    Detail: `notes/autohide.md`, `notes/workspaces.md`.
  - Fixed when: `lastIpcObject` follows the matching events.

- **`workspacev2` is applied to the *focused* monitor.** Moving a workspace
  to another output makes Hyprland switch the old output to a new
  workspace, and Quickshell credits that switch to the wrong monitor.
  - Seen: 0.3.x, observed.
  - Workaround: `shell.qml` refreshes monitors on `moveworkspacev2`. Detail:
    `notes/autohide.md`.
  - Fixed when: a workspace moved off a bar's output leaves that bar on the
    output's real workspace with the refresh removed.

- **Submaps exist only as `submap>>` events**, with no current-state
  property, so a shell built mid-submap sees none until the next change.
  - Workaround: `services/SubmapService.qml` seeds from `hyprctl -j submap`.
    Detail: `notes/layout.md`.
  - Fixed when: `Hyprland` exposes the active submap as a property.

- **`Hyprland.dispatch` in Lua mode wraps its string in `hl.dispatch(...)`**,
  so it can't carry a plain `hl.*` call.
  - Workaround: `shared/EdgeRelease.qml` runs `hyprctl eval` in a `Process`.
    Detail: `notes/autohide.md`.
  - Fixed when: a raw eval is available from QML.

## Screens and windows

- **An unplugged output's `ShellScreen` dangles instead of going null.** It
  stays truthy and emits no change, so `screen || fallback` never falls back
  (`qs log`: `attempted to use dangling screen object`).
  - Seen: 0.3.1, in the live log after a DP-2 unplug.
  - Workaround: `NotificationService` and `OsdService` clear any stored
    screen missing from `Quickshell.screens` on `screensChanged`.
  - Fixed when: a stored `ShellScreen` reads null after its output goes.

- **`Hyprland.monitorFor()` is a one-shot lookup.** A binding on it doesn't
  re-run when `Hyprland.monitors` changes. When an output drops out and comes
  back, the binding is left holding the deleted monitor or null, and stays
  there. The DP-2 bar's `workspace` stayed null, so auto-hide never matched
  there again until a reload.
  - Seen: 0.3.1, after DP-2 flapped (`qs log`: `Got removal for monitor
    "DP-2" which was not previously tracked`), 2026-10-03.
  - Workaround: `Screens.monitorFor()` finds the monitor by name in
    `Hyprland.monitors.values`, which notifies; `Bar.qml` and `scaleFor()`
    use it.
  - Fixed when: a binding on `Hyprland.monitorFor()` follows an output
    being removed and added back.

- **Layer-shell windows never get their real `QScreen`**, so Qt's animation
  driver reads the wrong vsync interval and drops every GUI-thread animation
  to about 60Hz.
  - Workaround: `//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1` in
    `shell.qml`. Detail: `notes/rendering.md` (FrameSpring is a separate,
    Qt-side cap and stays).
  - Fixed when: the default driver runs at the output's rate without the
    pragma, measured as in `notes/method.md`.

- **A `PopupWindow`'s `screen` isn't the output it's shown on.** A popup
  anchored to the bar on DP-1 read HDMI-A-1, so a scale looked up through it
  was 1.
  - Seen: 0.3.1, logged live from the weather popup (2026-09-29).
  - Workaround: `AnchoredPopupWindow` reads `_barScreen` off the anchor's
    window. Detail: `notes/style.md` (`snapSurface()`).
  - Fixed when: a popup's `screen` matches its anchor window's.

## Process and lifecycle

- **A `Process` that fails to start only clears `running`**; `exited` never
  fires, so a retry hung on `onExited` never runs.
  - Seen: 0.3.1, `src/io/process.cpp` (`onErrorOccurred` emits only
    `runningChanged`; `onFinished` emits `exited`, then `runningChanged`).
  - Workaround: `BacklightService`'s resync, `MpdService`'s idleloop restart
    and `EdgeRelease`'s retry act on `running` falling. Detail:
    `notes/backlight.md`, `notes/limitations.md`.
  - Fixed when: a failed start emits `exited` (or an error signal).

- **No SIGTERM handling, and no QML hook tells quit from reload.**
  `Component.onDestruction` fires on reload too, after the new bars exist.
  - Workaround: the Hyprland Lua side reverts EdgeRelease on `layer.closed`.
    Detail: `notes/autohide.md`.
  - Fixed when: QML can run on quit, distinct from reload.

- **`PersistentProperties` only persists as a direct child of a
  `Singleton`/Scope.** Detail and probe: `notes/qml-gotchas.md`.
  `NotificationService` is a `Singleton` for this.
