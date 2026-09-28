# Backlight

## How `BacklightService` works

- **Device discovery: `Qt.labs.folderlistmodel`.** `FolderListModel` over
  `file:///sys/class/backlight` with `showDirs: true` lists the class
  entries — they're symlinks into `/sys/devices/…`, and QDir follows them, so
  they come back as directories, not files (`showFiles: false` still lists
  them). Nothing else in Quickshell 0.3.1 can enumerate a directory; `FileView`
  is files-only. Verified under `quickshell -p`.
- **Device ranking**, from Noctalia (`src/system/brightness_service.cpp`,
  C++, so only the idea was portable): any device beats `acpi_video*` (a
  mirror of another device), and that beats `nvidia*` (often a stub). That is
  `rank()`; ties go to the name sort.
- **Values: two `FileView`s** on `brightness` and `max_brightness`. `reload()`
  re-reads and fires `onLoaded` every time, even when the bytes are
  identical, so the parse lives in `onLoaded`. No `blockLoading`: the async
  path lands within a frame. `brightness` is watched (`watchChanges: true`,
  `onFileChanged: reload()`) — see the inotify section below. Nothing polls.
- **The perceptual curve is in QML**: `percent = (raw/maxRaw) ^ (1/exponent)`
  on read (`exponent: 4`), inverse on write, so it doesn't depend on the
  installed brightnessctl having `-e`. Two details at the dark end:
  - A step rounds to an integer raw value and can land back on the current
    one, so `nudge()` forces ±1 raw and the wheel never feels dead. A zero
    delta does nothing (it used to force -1; 2026-09-28).
  - Writes clamp to `minRaw: 1`: raw 0 switches the panel off with nothing
    but another backlight write to undo it.
- **Two entry points, both through `nudge(delta)`** (perceptual units, 0..1):
  - `bump(steps)`: signed wheel notches, `step: 0.05` each. The bar module
    feeds it whole notches from `NotchWheelArea`.
  - `bumpPercent(points)`: perceptual points, the unit the old `brightnessctl
    -e s ±N%` binds moved in, for the `osd brightness` IPC call.
- **Writes shell out to `brightnessctl`, only on input.** The sysfs node is
  `root:root 0644`, so an unprivileged write needs brightnessctl's
  logind/setuid helper. Called argv-style, `-d <device>`, no `sh -c`.
- **`raw` updates optimistically before the write runs**, so the label tracks
  the wheel. A burst coalesces: `Process.exec()` on a running `Process` isn't
  a queue, so the latest target is parked in `pendingRaw` and flushed
  `onExited`, which also re-reads the file to resync.

## sysfs backlight does emit inotify (2026-09-06)

The service used to poll `reload()` from a 1s timer, on a written-down belief
that `sysfs_notify`/`poll(2)` is invisible to inotify and `watchChanges` could
never fire on `/sys/class/backlight/*/brightness`.

Noctalia does `inotify_add_watch(<device>/brightness, IN_MODIFY)` in
production (`brightness_service.cpp:945`), which was reason enough to re-test.
Both halves confirmed on this machine:

```
$ inotifywait -m -e modify /sys/class/backlight/dp_aux_backlight/brightness
  → MODIFY on every external brightnessctl write
```

and a standalone `qs -p` probe with `FileView { watchChanges: true }` on the
same path logged `FILECHANGED` + the new value for all three external changes,
immediately. The 1s timer was deleted.

**Open question (2026-09-28 review, unverified).** Every change in that test
was a *userspace write* to `brightness`, and a write syscall raises
`IN_MODIFY` on any file by itself. The kernel's own path for a change made
inside it — `backlight_force_update()`, used by acpi_video hotkeys and some
firmware-handled Fn keys — calls `sysfs_notify(…, "actual_brightness")`, not
`brightness`. So the watch may miss brightness changed by firmware keys, and
the `kernfs_notify` mechanism written here before may be the wrong reason for
a right result. Watching `actual_brightness` as well would cover both. Needs a
machine where firmware handles the keys to confirm.

**Lesson (a repeat of the `pw-dump` one in `notes/privacy.md`):** an empirical
"confirmed" negative can encode the wrong mechanism. The original test really
did fail, but the write-up blamed sysfs-vs-inotify in general rather than
whatever went wrong in that one probe. A second implementation doing the thing
you wrote off as impossible is the cheapest signal to re-run the experiment.

## Rejected

- **`sh -c "cat …/brightness; cat …/max_brightness"` every 5s**, the original
  implementation: a fork, a shell and two `cat`s per tick, forever, for a
  number that almost never changes.
- **A 1s `reload()` timer**: built on the wrong belief above; the watch
  replaced it.
- **`brightnessctl --exponent` for the curve**: ties the curve to the
  installed brightnessctl's version.
- **Writing the sysfs node directly**: it's root-owned.
- **Allowing raw 0**: switches the panel off.
