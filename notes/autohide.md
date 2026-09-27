# Bar auto-hide

Hides the bar on chosen workspaces, to keep a static strip off an OLED.
Config and IPC live in `shell.qml` (`barHideOn`, `barHideDelay`, the `bar`
IpcHandler); the state machine lives in `modules/Bar.qml`.

## Model

The bar on an output is hidden when, first match wins:

1. its **output override** (`visibility <action> <monitor>`) is set;
2. its current workspace has a **workspace override**
   (`visibility_workspace …`) — keyed by workspace *name*, so it follows the
   workspace to any output;
3. `barHideOn["*"]` or `barHideOn[<monitor>]` lists the workspace. A number
   matches the id, a string the name. They are not interchangeable here:
   ids 1-8 are named `a s d f u i o p`, and id 10 is named `"8"`.

Output beats workspace because the user asked for the output call to hide
"completely". `toggle` sets the opposite of what that level shows now, except
that it clears the override instead when the level below would already give
that state — two toggles always get back to auto. Overrides are in memory: a
reload drops them. Both maps live in `shell.qml`, keyed by name, so an output
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

## Rejected

- **Hide after N minutes without a workspace switch.** Resizes windows at an
  arbitrary moment, mid-reading; the per-workspace rule targets the actual
  case (a Firefox workspace left up for hours).
- **Drive hiding from Hyprland's Lua config over IPC.** Push-based state goes
  stale on a Quickshell reload and duplicates what Quickshell already tracks.
- **Overlay the bar during the hide delay with space already released.**
  Covers the Firefox tabs just switched to.
- **Flip the reserved space during Hyprland's workspace slide.** No hook.

## Gotcha: the action `show`

`qs ipc call bar visibility show DP-1` fails — Quickshell's CLI parser takes
`show` as its `qs ipc show` subcommand even in argument position. Pass `--`
before the arguments: `qs ipc call bar visibility -- show DP-1`.
