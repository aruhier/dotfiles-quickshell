# Workspaces

## Where the module's mechanics are written down

- Colours per state, `active` vs `focused`, the centre cap, button width and
  the shared `selection` indicator: `notes/style.md`.
- The five coupled springs on one `SpringGroup` clock, and rounding their
  output into non-antialiased edges: `notes/rendering.md` ("SpringGroup",
  "Round the output"), and why it isn't a `BarModule`: `notes/conventions.md`.
- The sliding indicator's binding trap (`itemAt()` paired with
  `repeater.count`): `notes/qml-gotchas.md`.
- Clicking dispatches `hl.dsp.focus({workspace, on_current_monitor})` rather
  than `HyprlandWorkspace.activate()`, which lacks `on_current_monitor` and
  sends the name as a selector, where a numeric name like "8" reads as id 8
  (comment at `focusOnCurrentMonitor`). The id is sent only when positive: a
  `name:` workspace's id is negative (-1337 and down), and `workspace =
  -1337` is read as a relative move — tested 2026-09-28, it took DP-1 from
  `f` to `a` instead of to the named workspace. Those go as
  `"name:<name>"`, which brought it over as expected.

## Workspace hover previews via per-window screencopy (2026-09-11)

`Workspaces.qml` pills open a `WorkspacePreviewPopup` on hover: a
monitor-aspect canvas (`WorkspacePreviewPopup.qml`'s `previewWidth`, 560px) with one
`Quickshell.Wayland.ScreencopyView` per window, placed from `hyprctl`'s
`at`/`size`. What was checked before building it, all on Hyprland 0.56.2 /
Quickshell 0.3.1:

- **There is no "capture a workspace" primitive.** Hyprland exposes
  output capture and per-window capture (`hyprland_toplevel_export_v1`,
  `ext_foreign_toplevel_image_capture_source_manager_v1`), nothing
  in between, so the preview composes windows itself.
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
  nothing about stacking, so the popup stacks tiled < floating <
  fullscreen, each by `focusHistoryID` descending (0 = most recent, on
  top) — as each delegate's `z`, not by sorting the model (2026-09-20).
  The Repeater's model is the bare `toplevels.values`, which only changes
  when a window comes or goes. Hidden/unmapped windows keep a delegate, invisible, not
  `live`, and with no `captureSource`: setting a source makes
  `ScreencopyView::createContext()` capture one frame even when not live.
- **Empty workspaces get no popup at all** (`HoverPopupArea.popupEnabled`),
  so hovering one builds nothing. Teardown is keyed on `HoverPopup`'s
  `dismissed` signal (after the fold, or on `close()`), not on `visible`
  going false — see Rejected.
- **A click on a pill calls `HoverPopupArea.cancel()`** before activating
  the workspace, which closes via `HoverPopup.close()`. `close()` now also
  deactivates itself with `PopupCoordinator`: it's followed by LazyLoader
  teardown, and a coordinator still pointing at the destroyed popup would
  call `close()` on it at the next hover popup's `activate()`.
- **Cost**: views only exist inside the popup, one workspace at a time,
  destroyed on close. Buffers are dmabuf at the window's physical size
  (e.g. 2931x1786 for a full-height window at scale 1.6), never CPU
  copies (`constraintSize` doesn't shrink them, see Rejected).
- **A window can sit in two workspaces' `toplevels`** (2026-09-28 review,
  read in Quickshell 0.3.1's `connection.cpp`): `refreshToplevels()` calls
  `setWorkspace(new)` and `insertToplevel()` on the new workspace but never
  removes the window from the old one's list — only a `movewindowv2` event
  does. A pinned window is *not* a case: on Hyprland 0.56 it sends
  `movewindowv2` each time it follows the workspace (tested live with a
  probe instance, 2026-09-29). What still leaks is a refresh racing a move:
  if the refresh's reply lands first, it re-points `t.workspace`, so the
  move's `movewindowv2` takes the window off the *new* list and puts it
  back, and the old list keeps it until the window closes or the workspace
  is destroyed (inferred from the handler, not reproduced). The pill's
  count, the popup's `shows()` and Bar's auto-hide count all check
  `t.workspace` against their own workspace, and the Repeater model stays
  the bare list so no view is rebuilt.
- **Monitors are refreshed on open too**: `x/y/width/height/scale` and
  `lastIpcObject.transform` only update in `refreshMonitors`, which runs on
  `configreloaded`, `monitoraddedv2` and shell.qml's `moveworkspacev2`
  handler — a runtime scale or rotation change may emit none of those.

## Rejected

- **Output capture for the preview**: it only ever shows the workspace
  currently on that monitor, plus the bar.
- **Filtering or sorting the Repeater's model** off `lastIpcObject`: the
  refresh on open rewrote every entry, rebuilt the array and recreated every
  `ScreencopyView` — two capture set-ups per hover. Visibility and stacking
  are per delegate instead.
- **`ScreencopyView.constraintSize`** to shrink buffers: didn't, in a probe.
- **Tearing the popup down when `visible` goes false**: a popup built while
  its windows are all hidden, or its monitor briefly null in a hotplug, never
  becomes visible, so it leaked with its captures running (2026-09-28).
- **`HyprlandWorkspace.activate()`** for a click: see above.

