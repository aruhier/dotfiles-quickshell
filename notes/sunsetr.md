# Sunsetr

`modules/Sunsetr.qml` over `services/SunsetrService.qml`: replaces
`gammastep-indicator`'s tray icon with the same features — the state at a
glance, a click to enable/disable, and the period, colour temperature and
location on hover (plus next change, gamma when not 100%, and the preset when
not `default`, which sunsetr has and gammastep didn't). Placed in `mainLayout`
only, where the tray icon used to be.

## Event source

sunsetr (0.12.6) broadcasts on `$XDG_RUNTIME_DIR/sunsetr-events.sock`, one
JSON object per line; a new client gets a `state_applied` with the current
state straight away. A Quickshell `Socket` reads it directly, so there is no
`sunsetr status --json --follow` subprocess. Events
(https://psi4j.github.io/sunsetr/advanced/ipc.html):

- `state_applied`: `active_preset`, `period`, `state` (`stable` |
  `transitioning`), `progress` (transitioning only), `current_temp`,
  `current_gamma`, `target_temp`/`target_gamma` (transitioning only),
  `next_period` (RFC 3339 with nanoseconds, which JS `Date` won't parse, so
  the fraction is cut to ms first)
- `period_changed`: `from_period`, `to_period`
- `preset_changed`: `from_preset`, `to_preset`, `target_*`
- `config_changed`: `target_*` (e.g. after `sunsetr set`)

Periods: `day`, `sunset`, `night`, `sunrise`, `static`. Mode and location
aren't on the socket: they come from `sunsetr get --json transition_mode
latitude longitude` (active preset), on connect and on preset/config change.

## Enabled = connected

"Disabled" means the daemon isn't running: sunsetr has no pause, and
stopping it resets gamma to neutral, which is what gammastep's toggle did.
The click runs `sunsetr stop` (stops an instance started outside systemd too)
or `systemctl --user start sunsetr.service` (so the daemon isn't a child of
the shell). After a start the toggle connects as soon as its command exits;
after a stop it doesn't try, the socket being gone.

Connects are keyed on `$XDG_RUNTIME_DIR/sunsetr.lock` (a `FolderListModel`
with that name filter, so inotify, no poll): a clean exit removes both the
lock and the socket, so a stopped daemon gets no connect attempts, each of
which would log a warning (`notes/quickshell-quirks.md`). With the lock up and
no connection, a timer retries from 1s, doubling to 10s, and resets on a
connect. The cap is low because a killed instance leaves its lock, and the
next instance likely reuses that file: its arrival raises no change in the
model, so only the timer finds it. The lock appears just before the socket,
so a start still logs one `ServerNotFoundError`, and a stop one
`PeerClosedError` (seen 2026-11-18).

On disconnect every socket-fed field resets, and until the first
`state_applied` lands (`period` still `""`) the module shows the neutral bulb
and "Connecting…", not the last session's values.

The module hides only when `sunsetr` isn't on PATH (checked once at start),
not when it is stopped: it has to stay clickable to start it again.

## Right-click menu

"Enabled" (the left click's toggle, with its state on the right) and
"Suspend for" 30 min / 1 / 2 / 4 / 8 h, as one flat list of `MenuRow`s: what
the user kept of gammastep-indicator's menu (Autostart, Info and Quit
dropped; the tooltip already is the info). A `HoverPopup` whose
`anchorHovered` is the module's `menuOpen` (set by a right click) and its
hover, so it gets the same plate and unfold, and from there behaves as a hover
popup: it stays while the cursor is on the bulb or the menu and folds once it
leaves both. A pick, a second right click or a left click closes it at once
(`closeMenu()`), and another hover popup opening takes it over. A pick runs
its action before closing, since `close()` tears down the rows. Quickshell 0.3.2 has no QML-built native menu
(`QsMenuAnchor` takes a D-Bus menu handle), hence the popup.

A suspend stops sunsetr and creates `sunsetr-resume.timer` with
`systemd-run --user --collect --on-calendar="<UTC time> UTC"`, which starts
`sunsetr.service`. An absolute time, not `--on-active`: that one runs on the
monotonic clock, which stops during sleep, and its `NextElapseUSecRealtime`
reads empty, so the resume time couldn't be read back. UTC, not local, so
the hour a DST fall-back repeats can't make it ambiguous (`systemd-analyze
calendar` takes the suffix). `--collect`, because a resume whose start failed
would otherwise stay loaded as failed, and its name would block every later
suspend (flagged in review, not reproduced).

Read back with `systemctl --user show sunsetr-resume.timer -p
NextElapseUSecRealtime --value --timestamp=unix` ("@<seconds>", empty
without one) at start and after every command, so "Suspended until"
survives a reload; and every 30s once the time has passed, in case the timer
fired without bringing sunsetr back. A fired calendar timer unloads itself;
an earlier one is stopped before a new suspend, since a loaded transient
unit's name can't be reused (tested with a dummy unit, 2026-11-18).

Enabling cancels the timer, and so does sunsetr connecting while one is
pending (started by hand); a read-back that finds a timer while sunsetr runs
cancels it as a leftover, except the one right after our own suspend
(`ownSuspend`), which can land before the socket notices the stop.

## Glyphs

MDI lightbulbs: filled (0xf0335) in the group text colour whenever the
screen is warmed (night, sunset, sunrise, static); outline (0xf0336) in
`Theme.text`, the dimmed colour do-not-disturb uses, whenever it is neutral —
day, stopped or still connecting, deliberately the same icon (the tooltip
tells them apart).
Not the sun and moon: Weather already uses them (0xf0599/0xf0594), and the
two would read as the same thing side by side.

First sized against gammastep-indicator's tray icon (Papirus
`panel/gammastep-status-on`, drawn by Tray at 14 logical px; its bulb fills
the box): 18 physical px of ink centred at y=13.5 on DP-1 at 1.25, matched by
`iconSizeRatio: 1.1`, `iconVerticalOffset: 1`. The user then set 0.9 / 0.8 by
eye; those are the values in the file. Measured with a column/row ink scan of
a `grim` crop, 2026-11-18.

The bulb is a `shared/InkIcon`, sized to its ink rather than its cell; why,
and the gaps measured, in `notes/style.md`.

## Verified (2026-11-18)

On DP-1: filled bulb while running at night; stopping showed the faded
outline within ~1s; `systemctl --user start` brought the filled bulb back
within ~1s; the tooltip read "Night · 3500 K / Sunrise at 07:24 / Location:
47.4, 8.6". Not exercised live: a real sunset/sunrise transition, and preset
switches.

## Rejected

- **Closing the menu on an outside click with `HyprlandFocusGrab`** over the
  popup and the bar (2026-11-18). With the grab active the popup got no
  pointer input at all: no row hover, no click, the popup's own surface never
  saw the cursor enter. Off, every row reported its hover. See
  `notes/quickshell-quirks.md`. A screen-sized click catcher behind the menu,
  as the control center has, was the other way; the user preferred
  close-on-leave.
- **A blind 5s reconnect timer** (the first version). Each failed connect
  logs a warning, so the log filled for as long as sunsetr was stopped.
- **Watching `sunsetr-events.sock` instead of the lock**, suggested in
  review to also drop the one warning per start. `FolderListModel` doesn't
  list sockets: a test dir holding `test.lock` and a bound `test.sock`, both
  in `nameFilters`, gave a count of 1, the lock (2026-11-18).
