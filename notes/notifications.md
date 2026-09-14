# Notifications

## Native notification daemon, replacing swaync (2026-09-03)

The bar used to only have a thin swaync *indicator* (`swaync-client -swb`
for the badge, `-t/-d -sw` to toggle swaync's own GTK panel) — the actual
DBus `org.freedesktop.Notifications` daemon, popup toasts, and
control-center panel were swaync's separate GTK process. All of that now
lives natively in this shell: `services/NotificationService.qml` (the
daemon + all state) plus `shared/notifications/` (the popup stack and
control-center panel windows, and the shared `NotificationCard.qml` view
both render notifications with). `modules/NotificationCenter.qml` (was
`SwayNC.qml`) is still just the thin bar-indicator view, same shape as
before, now reading the new singleton instead of shelling out.

**Requires `Quickshell.Services.Notifications`, which is a compile-time
option.** This machine's Quickshell (`gui-apps/quickshell` in the local
guru overlay) was built with `USE=-notifications` — the module simply
didn't exist at `/usr/lib64/qt6/qml/Quickshell/Services/Notifications/`
until the package was rebuilt with `USE=notifications`. If notifications
mysteriously stop working after a Quickshell upgrade, check the USE flag
first before assuming a code regression.

**swaync had to be actively stopped, not just left running** — only one
process can own the DBus name. Two things had to happen, not one:
1. Kill the running process (`pkill -f swaync`) — but it came back on its
   own within minutes.
2. The respawn was systemd D-Bus activation: `swaync.service` (a
   *different* launch path than the `swaync&` line in
   `~/dotfiles/hypr/scripts/start`, which is how it's normally started)
   is D-Bus-activatable, so the moment anything touched the
   `org.freedesktop.Notifications` name with no owner present, systemd
   auto-spawned it via that unit — independent of whether the unit is
   "enabled" for login-time startup. Fix: `systemctl --user mask
   swaync.service` (reversible with `unmask`), *then* kill the process.
   `pkill` alone is not sufficient against a D-Bus-activatable service.
   The `~/dotfiles/hypr/scripts/start` autostart line itself was
   deliberately left alone (not this shell's file to edit, and swaync may
   still come back at next login until that's addressed separately).

**Architecture mirrors this repo's usual split**: `NotificationService.qml`
(pragma-Singleton) owns the `NotificationServer` and every list/timer;
`shared/notifications/*` are thin views reading it. Deliberately simpler
than swaync itself, and simpler than DankMaterialShell's much heavier
notification service (read for API-usage reference only, per the existing
lesson in `notes/conventions.md` about not blindly copying DMS's reasoning):
flat history with no grouping/dedup, and `dnd` kept in-memory rather than
GSettings/dconf-backed like swaync's own — depending on swaync's schema
surviving would be a fragile link for a system meant to replace it
outright.

**The mpris widget is genuinely generic MPRIS, not MPD-specific** — an
earlier draft of this had `MpdService.qml` grow `mpc`-shelled
play/pause/album-art methods for it, which was the wrong layer: swaync's
own mpris widget is a generic MPRIS client (shows whatever's active over
MPRIS), not tied to MPD. Reverted that `MpdService.qml` detour entirely
and used `Quickshell.Services.Mpris` (`Mpris.players.values`, preferring
a currently-`isPlaying` player and falling back to the first available
one) instead — this machine already has `media-sound/mpd-mpris` installed
to bridge MPD onto MPRIS (`systemctl --user start mpd-mpris.service`),
so this widget picks it up like any other MPRIS player for free, with no
MPD-specific code in the bar at all.

**`NotificationCard.qml`'s height must include the actions row, not just
the main content column.** First version computed
`implicitHeight: mainColumn.implicitHeight + padding * 2` and anchored
the action-buttons row to `parent.bottom` independently — on a
notification with action buttons, the actions row silently overlapped
and visually replaced the last line of body text instead of appending
below it (card height never grew to make room). Fixed by anchoring the
actions row to `mainColumn.bottom` instead of `parent.bottom`, and
folding its height into `implicitHeight` when visible. Caught by
screenshot-testing an actions-bearing notification, not by the QML engine
— no warning is logged for an item that's merely undersized, only for
missing properties/types.


## IPC for the notification panel (2026-09-03)

`shell.qml` now has a top-level `IpcHandler { target: "notifications" }`
exposing `toggle()`/`open()`/`close()`/`clear()`, so a Hyprland keybind can
drive the control-center panel the same way the bar indicator's click does:

```
bind = SUPER, N, exec, qs ipc call notifications toggle
```

(`qs ipc call` needs `-p <path>`/`-c <name>` if this config isn't the
`default` one — see `quickshell ipc --help`.)

`toggle()`/`open()` reuse `NotificationService.toggleCenter(screen)`, the
same function `NotificationCenter.qml`'s click handler calls — just with
Hyprland's *focused* monitor as the screen instead of the screen the
clicked widget happens to live on, since an IPC call has no
widget/screen of its own to report (added `root.focusedScreen()` in
`shell.qml`, resolving `Hyprland.focusedMonitor.name` through the existing
`screenByName()`, falling back to `mainScreen`). `open()` is idempotent
(no-ops if already open, doesn't retarget it to the focused screen);
`close()` calls `NotificationService.closeCenter()` directly, unconditional
regardless of which screen it's open on. `clear()` calls the existing
`NotificationService.clearAll()` — dismisses every notification in history
and, per that function's own pre-existing bulk-clear behavior, closes the
panel too. Verified live against the running instance: `quickshell ipc -p
<path> show` lists all four functions; `close`/`open`/`open`-again
(idempotent)/`toggle` round-tripped correctly (checked via `hyprctl layers
-j | grep -c quickshell-notification-center`); `clear` tested by firing a
real `notify-send`, opening the panel, then confirming both the toast and
the panel-close happened.

**Testing gotcha: `notify-send -A` needs `NAME=Text`, not `NAME,Text`.**
`-A "default,Open"` doesn't error — it silently becomes one action whose
whole `identifier`/`text` is the literal string `"default,Open"`, which
then fails the `identifier === "default"` default-action check and
(correctly, given that input) falls through to being rendered as an
ordinary action button. Correct form: `-A "default=Open"`. Separately,
`-A` implies `--wait`, so a `notify-send` call using it blocks until the
notification is closed — background it (`timeout N notify-send ... &`)
during manual testing or the shell command hangs.

