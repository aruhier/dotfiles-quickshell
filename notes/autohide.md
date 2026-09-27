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
"completely". `toggle` in auto forces the opposite of what that level shows
now; while forced, it always goes back to auto. When the override agrees with
auto (an output forced shown, then switched to a workspace that shows it
anyway), that press changes nothing visible; the OSD says "auto". The first
version flipped the state every time and only cleared when the flip matched
auto, so that press forced the other way — e.g. hid the bar on every
workspace of the output. The user preferred toggle to mean "leave auto / go
back to auto". Overrides are in memory: a
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
- **Rule-driven hide waits `barHideDelay` (1s)**, then slides up — so a
  workspace only passed through never resizes anything. The delay restarts while
  anything holds a peek (below): the cursor on the bar, or something it
  opened. Started at 1.5s; the user shortened it to 1s. It's
  one number in `shell.qml`.
- **Space follows `hiddenAfterDelay`, not the slide**: given up as the bar
  starts up, reserved as it starts down, so windows move with the bar both
  ways. The bar is on Top and opaque, so a window growing under it is
  covered. Hiding used to release only once the bar was out of sight
  ("windows grow into an empty strip"): measured with grim bursts on DP-1,
  the bar left by ~60ms, then a wallpaper strip stood still ~300ms before
  the window grew — two motions. Now the space goes ~11ms after the IPC call
  and the strip shrinks from ~70ms and is closed by ~160ms: Hyprland's
  `windowsMove` (speed 3, ~300ms) trails the ~170ms spring, so it doesn't
  quite track the bar's edge. Matching them was left for if it shows.
- **Showing is immediate**: the switch was made to see it.
- **Cold start applies the first workspace as is.** Hyprland's state arrives
  after the bar is built, so without `settleFirstWorkspace()` a shell started
  on a hide-listed workspace would show the bar, wait, then resize every
  window. A reload hides this — the data is already there.
- **IPC calls skip the delay** (`skipDelay()`). The `visibility*` calls
  also flash the OSD's `message` kind with the new state, on the target
  output.
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
- **Timed peek** (`qs ipc call bar peek <seconds> <monitor>`): the same
  peek, held by `peekTimed` for that long. At the end it goes with no grace,
  unlike the panel's hand-over, unless the cursor is on the bar — even one
  the peek slid the bar under — then it hands over to `peekLatched`.
  - During the hide delay it skips the delay, so the peek lasts the full time.
  - On a shown bar it returns "nothing to peek". A second call restarts it
    with the new time. No OSD: the bar showing up is the feedback.
  - Ends early when the bar is shown for real, or on a `hide` (or a `toggle`
    landing on hidden) — at once, even under the cursor. A cursor or panel
    peek stays. `auto` or a masked `unhide` ending hidden don't end it.
  - Capped at a day: `Timer.interval` is an int, and an overflowed one never
    fires.
- `peeking` is derived
  (`hiddenAfterDelay && (peekLatched || panelOpenHere || peekTimed)`), not
  written by handlers: an earlier stored flag reset in `onHiddenChanged`
  could leave the bar's state wrong for one turn.
- The spring is stiff (900/46.5) because a fade on FrameSpring's default
  tuning, when space was released after it, measured ~550ms to release.
- Toasts drop their bar offset on an output whose bar isn't reserving space.
  The move is a margin change, so it jumps rather than slides, and during a
  peek the bar can overlap a toast; both accepted. The control centre needs
  nothing: it's placed from the screen edge.
- `moveworkspace` and `moveworkspacev2` both fire per move; only v2 triggers
  the refresh.

Switching `exclusionMode` Auto↔Ignore live is a plain commit in Quickshell,
no remap. The hidden surface stays mapped and transparent; nothing renders
at rest.

## Edge-to-edge window (`quickshell.bar_autohide`)

When the bar gives up its space over exactly one tiled window, that window
also loses `gaps_out`, border and rounding. `shared/EdgeRelease.qml` (one per
Bar) calls `quickshell.bar_autohide(output, name)` in
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
- **Leaving keeps the release** (`releasedWorkspace`): the workspace stays
  flush while it would still hide the bar here — same output, `shouldHideOn`,
  one tiled window — and is reverted the moment any of that stops holding,
  even unseen. A round trip 1→4→1 thus makes no call: back on it, the window
  sits flush under the reserved bar (Hyprland lays out every workspace of the
  output against the zone, `LayoutManager::invalidateMonitorGeometries`), and
  grows after the delay. Measured on DP-2: 0 calls, `0,26 2560x1414` then
  `0,0 2560x1440`. The Lua side holds one workspace per output, so going
  from one hide-listed workspace straight to another still moves the rule.
  Peeking the bar over the still-released window on return was weighed
  first; the user chose this. The zone is per output, so the peek would only
  move the resize into the workspace slide, and it covers the tabs (Rejected).
- **Selected by name** (`name:<name>`), which matches numbered workspaces by
  their name too (checked: `name:7` hits id 9). `r[from-to]` would reject
  the negative ids of named workspaces: `Workspace.cpp` fails the selector
  when a bound is < 1, and only logs it at debug level.
- **One rule per workspace, toggled** (Hyprland 0.56.2): the first release of
  a name creates its rule, and the Lua file keeps the handle
  `hl.workspace_rule` returns; after that only `rule:set_enabled()` is called.
  A disabled rule is skipped by every lookup (`WorkspaceRuleManager.cpp`),
  so the revert falls back to the config's gaps with no values copied in.
  Rules can't be deleted from Lua, only cleared by a config reload, which
  also resets the table of handles. `enabled = false` in the table is
  ignored: `replaceOrAdd` merges it into the enabled rule with the same
  selector, and `mergeLeft` doesn't carry the flag. Measured: one `name:a`
  rule through open/close of a second window and a round trip. Both
  directions land exactly on a visible workspace (full `3072×1728` on DP-1,
  `2564,30` back), with no extra call: the rule change schedules Hyprland's
  prop refresh itself.
  `hl.exec_scheduled_prop_refresh_immediately()` was called after it at
  first, from a test on an unseen workspace that came back 2px off. That
  test proved nothing about visible ones: the window was left unseen. Without
  the call, both directions were exact on a visible workspace, and even the
  unseen one corrected itself ~1.5s later. Removed.
- **Every runtime rule re-places persistent workspaces** (0.56.2): each
  `hl.workspace_rule` schedules `REFRESH_MONITOR_STATES`, which runs
  `ensurePersistentWorkspacesPresent()`. That moves every persistent
  workspace to its rule's monitor, or to the *focused* one if the rule has
  none. Workspace 1, pinned to DP-1 and focused on DP-2 via
  `on_current_monitor`, jumped back to DP-1 as soon as its bar released it.
  `set_edges` first re-points the rules of all persistent workspaces (1 to
  `last_persistent` in the Lua file; Lua can't read rules back) at the monitor
  each is on, so the refresh finds nothing to move. A config reload still
  sends 1-3 home. 4-8 were left unpinned at first, which the rule's empty
  monitor turns into "the focused one" (`WorkspacePlacementController.cpp`):
  a second window opened on DP-2's `a` reverted it and pulled all of 4-8 to
  DP-2, `f` off DP-1 with them. Pinning them has a cost: the pin is only as
  fresh as the last call, and Hyprland's other refreshes (a monitor
  reconnecting, scrolling fullscreen) send them back to it. Clearing a monitor
  from a rule isn't possible: `mergeLeft` skips empty fields. A monitor name
  that doesn't exist would make the refresh skip them, but also drop their
  persistence. Toggling a rule schedules the same refresh
  (`LuaWorkspaceRule.cpp`), so the handles don't avoid it. Still so on
  upstream `main` at `4bb6844b` (2026-09-27): the fallback to the focused
  monitor is in `state/workspace/PlacementController.cpp`, for workspaces
  that already exist too.
- **Reverts usually land off screen**: they come from a hidden workspace
  gaining a window, an override, or a move to another output. Harmless:
  every workspace of the output is re-laid out on each change anyway.
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

- **Timed peek waiting out the hide delay.** Its timer ran alongside the
  delay, so the peek came out shorter than asked or never showed, and a
  leftover `peekTimed` could peek the next hide unasked.
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
