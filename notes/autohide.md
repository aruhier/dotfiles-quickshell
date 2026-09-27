# Bar auto-hide

Hides the bar on chosen workspaces, to keep a static strip off an OLED.
Config lives in `shell.qml` (`barHideOn`, `barHideDelay`), the `bar`
IpcHandler and the override maps in `Ipc.qml`, the state machine in
`modules/Bar.qml`.

## Model

The bar on an output is hidden when, first match wins:

1. its **output override** (`visibility <action> <monitor>`) is set;
2. its current workspace has a **workspace override**
   (`visibility_workspace …`) — keyed by workspace *name*, so it follows the
   workspace to any output;
3. `barHideOn["*"]` or `barHideOn[<monitor>]` lists the workspace **and it
   has exactly one tiled window**. A number matches the id, a string the
   name. They are not interchangeable here: ids 1-8 are named
   `a s d f u i o p`, and id 10 is named `"8"`.

The tiled count only gates the rule level: an IPC `hide` hides over any
number of windows. It counts windows, all of them, not only those on screen,
so each scrolling-layout column normally counts as one. Two windows stacked
in one column count as two, because Quickshell can't see columns. A tab
group counts once, by its first member (`grouped[0]`). Inactive tabs are
not `hidden` in 0.56; that flag is only set for swallowed windows and a few
X11 cases. An empty workspace shows the bar, so the first window opened
there resizes once, after the delay.

What gets counted (`floating`, `hidden`, `grouped`) is only in
`lastIpcObject`, which no event updates. So `shell.qml` refreshes toplevels
on `openwindow`, `closewindow`, `changefloatingmode` and the three group
events. The refresh is debounced by 50ms because Quickshell *drops* a
refresh asked for while one is in flight: two windows opening together could
leave the second one never fetched. A refresh that lands mid-flight can
still be lost; the next such event catches it up. A window not fetched yet
is *not* counted: counting it as tiled would bring the bar back for a second
whenever a floating dialog opens. The cost is ~50ms before a second tiled
window shows the bar.

Output beats workspace because the user asked for the output call to hide
"completely". `toggle` sets the opposite of what that level shows now, except
that it clears the override instead when the level below would already give
that state — two toggles always get back to auto. Overrides are in memory: a
reload drops them. Both maps live in `Ipc.qml`, keyed by name, so an output
override survives the monitor being unplugged (it was on the Bar instance at
first, and died with it).

Names, not ids, key the workspace overrides: Hyprland gives a named workspace
a new negative id (-1337 and down) every time it's created. A rename drops the
override; accepted.

## Special workspaces need no handling

Checked in Hyprland 0.56.2 and Quickshell 59e9c47: `focusedmon` reports the
monitor's regular workspace (`FocusState.cpp`), `changeWorkspace()` routes a
special one to `setSpecialWorkspace()` and returns before `workspacev2`
(`Monitor.cpp`), and Quickshell ignores `activespecial`. So
`HyprlandMonitor.activeWorkspace` is never special and the bar binds to it
directly; opening a scratchpad changes nothing, as the user wants.

One Quickshell quirk does matter: it applies every `workspacev2` to the
*focused* monitor. Moving a workspace to another output makes Hyprland switch
the old output to a new workspace, and that switch gets credited to the wrong
monitor. `shell.qml` calls `Hyprland.refreshMonitors()` on `moveworkspace*`.

## Motion and reserved space

Three modes: shown (reserves space), hidden, peek (overlay, reserves nothing).

- **One gesture for everything**: the bar lives just above the top edge and
  slides out of it — rule, IPC or peek. A fade for rule changes was tried
  first (on a UI review's advice to keep slides for the peek); the user
  preferred one motion, and every other surface here slides too. The spring
  is critically damped (~170ms) with no bump either way: the bar is flush
  with the edge, so an overshoot would open a sliver of gap above it.
- **Rule-driven hide waits `barHideDelay` (1s)**, then slides up, then
  gives up the space — so windows grow into an empty strip and a workspace
  only passed through never resizes anything. The delay restarts while
  anything holds a peek (below): the cursor on the bar, or something it
  opened. Started at 1.5s; the user shortened it to 1s. It's
  one number in `shell.qml`.
- **Showing is immediate**: space reserved at once, so windows move down with
  the bar as it comes down — one direction, not two unrelated motions.
- **Cold start applies the first workspace as is.** Hyprland's state arrives
  after the bar is built, so without `settleFirstWorkspace()` a shell started
  on a hide-listed workspace would show the bar, wait, then resize every
  window. A reload hides this — the data is already there.
- **IPC calls skip the delay** (`skipDelay()`) and flash the OSD's `message`
  kind with the new state, on the target output.
- **Peek** is the same slide without reserving space. Trigger is a 1px input
  strip (`mask`) at y=0: 250ms rest, restarted when the cursor runs
  more than 40px along the edge (outputs sit side by side, so the top edge is
  a path between them). `gaps_out` is 2 here, so the strip sits over the gap,
  not windows. Leave grace is 400ms. Held open while a hover popup
  (`PopupCoordinator.activeOwner`) or tray menu
  (`PopupCoordinator.trayMenuOwner`) anchored to *this* bar, or the
  notification panel on this output, is up. The tray icon clears its entry
  on destruction: an app quitting with its menu open may never send `closed`.
- **Opening the notification panel peeks the bar** on its output — a peek,
  not a show, since reserving space would resize every window on open and
  again on close. Closing it hands the peek to the grace timer, so the bar
  doesn't vanish from under a cursor already on it.
- `peeking` is derived (`hiddenAfterDelay && (peekLatched || panelOpenHere)`),
  not written by handlers: an earlier stored flag reset in `onHiddenChanged`
  could leave the bar's state wrong for one turn.
- Space release after an IPC hide measures ~300ms end to end, IPC round
  trip included. The fade that came before it, on FrameSpring's default
  tuning, measured ~550ms — hence the stiffer 900/46.5.
- Toasts drop their bar offset on an output whose bar isn't reserving space.
  The move is a margin change, so it jumps rather than slides, and during a
  peek the bar can overlap a toast; both accepted. The control centre needs
  nothing: it's placed from the screen edge.
- `moveworkspace` and `moveworkspacev2` both fire per move; only v2 triggers
  the refresh.

Switching `exclusionMode` Auto↔Ignore live is a plain commit in Quickshell,
no remap. The hidden surface stays mapped and transparent; nothing renders
at rest.

## Edge-to-edge window (`bar_released`)

When the bar gives up its space over exactly one tiled window, that window
also loses `gaps_out`, border and rounding. `shared/EdgeRelease.qml` (one per
Bar) calls `bar_released(output, name)` in
`~/.config/hypr/conf/workspaces.lua` (not in this repo) with `hyprctl eval`
on every change, passing `nil` once the bar takes its space back. The Lua
side keeps the per-output state and restores the previous workspace itself,
unless another output's bar still holds it (a moved workspace).

- **Why Quickshell drives it**: a static `w[tv1]` rule can't see whether the
  bar is hidden (rule, IPC override, delay). Keeping `w[tv1]` as well would
  make two predicates that disagree in timing: closing down to one window
  would drop the gaps at once and release the bar's space 1s later — two
  resizes. Gated on `reservesSpace`, both happen in one.
- **Peek changes nothing**: it doesn't touch `reservesSpace`.
- **Selected by name** (`name:<name>`), which matches numbered workspaces by
  their name too (checked: `name:7` hits id 9). `r[from-to]` would reject
  the negative ids of named workspaces: `Workspace.cpp` fails the selector
  when a bound is < 1, and only logs it at debug level.
- **Measured in Hyprland 0.56.2**: a runtime `hl.workspace_rule` with the same
  selector *merges* into the existing rule instead of appending, so the calls
  don't pile up. `enabled = false` is ignored, so the revert sets
  `gaps_out = hl.get_config("general.gaps_out")` and `no_border`/
  `no_rounding = false`. Both directions land exactly on a visible
  workspace (full `3072×1728` on DP-1, `2564,30` back), with no extra call:
  the rule change schedules Hyprland's prop refresh itself.
  `hl.exec_scheduled_prop_refresh_immediately()` was called after it at
  first, from a test on an unseen workspace that came back 2px off. That
  test proved nothing about visible ones: the window was left unseen. Without
  the call, both directions were exact on a visible workspace, and even the
  unseen one corrected itself ~1.5s later. Removed.
- **Reverts usually land off screen**: switching away is what makes the bar
  reserve again, so the revert reaches a workspace that's already hidden.
  Harmless: `Monitor::changeWorkspace` recalculates the layout on the way
  back. Recorded at 50ms resolution: the window lands at `2564,30` in the
  same sample as the switch, then at `2560,0` full size ~1.3s later, in one
  resize.
- **`Hyprland.dispatch` can't carry it**: in Lua mode it wraps the string in
  `hl.dispatch(...)`, which errors after running the rule, so it would only
  work by accident. Hence the `hyprctl` process. A failed call (non-zero
  exit, e.g. the function missing from the config) is logged.
- **No idle cost**: A/B on the same process, 60s each, with Hyprland's event
  count equal (252): 0.05% vs 0.03% of a core (3 vs 2 ticks), main-thread
  wakeups 6.8/s vs 6.5/s. Nothing runs without a window event or bar change.
- **Shell stopped**: the same Lua file reverts an output on `layer.closed`
  for `quickshell-bar` when no other bar surface is left on that monitor.
  So a quit, `systemctl stop` or crash doesn't leave a workspace gapless.
  Hyprland only knows the namespace, which its layer rules already name.
  - A Quickshell reload opens the new bar before closing the old one, or
    reuses the surface, so it never fires.
  - The closing surface is still listed in `hl.get_layers()` inside its own
    handler, hence the address check.
  - Tested with DP-1 flushed on `a`: two reloads kept it flushed, `stop`
    reverted it, `start` flushed it again.
  - Done in Hyprland because Quickshell can't: it doesn't handle SIGTERM
    (default action, no QML runs), and no QML hook tells quit from reload.
    `Component.onDestruction` fires on reload, 13ms *after* the new bars
    sent their state.
- **Resync**: a Hyprland config reload drops runtime rules and resets the
  Lua state, so EdgeRelease resends on `configreloaded`. It also sends once
  at start, which undoes a release left behind by a shell that died hidden.

## Rejected

- **Hide after N minutes without a workspace switch.** Resizes windows at an
  arbitrary moment, mid-reading; the per-workspace rule targets the actual
  case (a Firefox workspace left up for hours).
- **Drive hiding from Hyprland's Lua config over IPC.** Push-based state goes
  stale on a Quickshell reload and duplicates what Quickshell already tracks.
- **Overlay the bar during the hide delay with space already released.**
  Covers the Firefox tabs just switched to.
- **Flip the reserved space during Hyprland's workspace slide.** No hook.
- **Hide over an empty workspace too** (zero tiled windows). It would save
  the resize when the first window opens, but the user wants the bar there.
- **Shutdown cleanup inside Quickshell.** A per-bar `sh` watchdog on a stdin
  pipe that runs the revert at EOF works: a reload SIGKILLs it, SIGTERM
  closes the pipe. But it's an extra idle process per bar and too much
  machinery; `ExecStopPost=` in the systemd unit only covers the unit's `qs`.
- **Fake fullscreen** (`fullscreen_state` internal 2) instead of the rule.
  It's per window: it follows the window to other workspaces, fights a
  second window opening, and covers the Top layer the bar lives on, so peek
  would need Overlay.

## Why `unhide`, not `show`

`qs ipc call bar visibility show DP-1` fails — Quickshell's CLI parser takes
`show` as its `qs ipc show` subcommand even in argument position (`--` before
the arguments gets it through). The action was renamed to `unhide` rather
than leave that trap in every keybind.
