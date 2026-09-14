# Workspaces

## Workspace hover previews via per-window screencopy (2026-09-11)

`Workspaces.qml` pills open a `WorkspacePreviewPopup` on hover: a
monitor-aspect canvas (`Theme.workspacePreviewWidth` wide, 640px) with one
`Quickshell.Wayland.ScreencopyView` per window, placed from `hyprctl`'s
`at`/`size`. What was checked before building it, all on Hyprland 0.56.2 /
Quickshell 0.3.1:

- **There is no "capture a workspace" primitive.** Hyprland exposes
  output capture and per-window capture (`hyprland_toplevel_export_v1`,
  `ext_foreign_toplevel_image_capture_source_manager_v1`), nothing
  in between, so the preview composes windows itself. Output capture would
  only ever show the workspace currently on that monitor (plus the bar).
- **Windows on workspaces that aren't on any monitor still capture, and
  stay live.** The compositor re-renders the window offscreen for the
  capture and keeps feeding the client frames while a capture is running:
  a probe capturing a `foot` running `date` in a loop on an off-screen
  workspace showed the time line changing between two grabs 3s apart
  (`ScreencopyView { live: true }`). So no stale-snapshot caveat. The one
  thing that does go stale: a window *resized* while off-screen (e.g.
  tiled next to a new neighbour) keeps its old buffer until the client
  redraws, so its thumbnail is briefly stretched into the new slot.
- **Geometry is `HyprlandToplevel.lastIpcObject`, refreshed on open** with
  `Hyprland.refreshToplevels()` from the popup's `Component.onCompleted`
  (creation == open, since it's LazyLoader-built) — the same
  snapshot-goes-stale property that made Workspaces.qml count windows via
  `toplevels` instead of `lastIpcObject.windows`. `at`/`size` and monitor
  `x`/`y` are logical coordinates; `HyprlandMonitor.width`/`height` are
  the physical mode size, so divide `scale` back out (and swap axes on odd
  `transform`s).
- **Paint order**: hyprctl lists windows in creation order, which says
  nothing about stacking, so the popup sorts tiled < floating <
  fullscreen, each by `focusHistoryID` descending (0 = most recent, drawn
  last).
- **Empty workspaces get no popup at all** (`HoverPopupArea.popupEnabled`),
  rather than a popup that's built, never becomes visible, and so never
  hits the `onVisibleChanged` teardown.
- **A click on a pill calls `HoverPopupArea.cancel()`** before activating
  the workspace, which closes via `HoverPopup.close()`. `close()` now also
  deactivates itself with `PopupCoordinator`: it's followed by LazyLoader
  teardown, and a coordinator still pointing at the destroyed popup would
  call `close()` on it at the next hover popup's `activate()`.
- **Cost**: views only exist inside the popup, one workspace at a time,
  destroyed on close. Buffers are dmabuf at the window's physical size
  (e.g. 2931x1786 for a full-height window at scale 1.6), never CPU
  copies; `constraintSize` didn't shrink them in a probe, so it's unused.

Verification notes:
- `hyprctl dispatch` on 0.56 takes Lua (`hl.dsp.focus({workspace = "s"})`,
  `hl.exec_cmd(cmd, {workspace = "f"})` — no `silent` rule, so exec
  switches to that workspace). `hl.dsp.window.close({address = ...})`
  **ignored the address and closed the active window** — which was the
  terminal running the session. Kill test windows by pid instead.
- Grabbing a popup screenshot right after the hover lands catches
  Hyprland's popup fade-in and looks see-through; wait a beat.

