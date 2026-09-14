# Backlight

## BacklightService reads sysfs directly; no more `sh -c cat` polling (2026-09-05)

`services/BacklightService.qml` used to run `sh -c "…cat …/brightness; cat
…/max_brightness"` every 5s and hand the step math to `brightnessctl
--exponent`. A fork + `sh` + two `cat`s per tick, forever, to learn a number
that almost never changes. Now:

- **Device discovery: `Qt.labs.folderlistmodel`.** `FolderListModel` over
  `file:///sys/class/backlight` with `showDirs: true` lists the class
  entries — they're symlinks into `/sys/devices/…`, and QDir follows them, so
  they come back as directories, not files (`showFiles: false` still lists
  them). Nothing else in Quickshell 0.3.1 can enumerate a directory; `FileView`
  is files-only. Verified under `quickshell -p`.
- **Values: two `FileView`s** on `brightness` and `max_brightness`. `reload()`
  re-reads and fires `onLoaded` every time, even when the bytes are identical —
  so the poll handler is just `reload()` and the parse lives in `onLoaded`. No
  `blockLoading` needed; the async path already lands within a frame.
- **Polling stays, because sysfs has no inotify.** ~~Backlight attributes
  signal readers through `sysfs_notify`/`poll(2)`, which
  `FileView.watchChanges` (inotify) can't observe — a watch there simply never
  fires.~~ **Wrong — corrected 2026-09-06, see the section at the end of this
  file. There is no poll timer any more.**
- **Writes still shell out to `brightnessctl`, but only on user input.** The
  sysfs node is `root:root 0644`, so an unprivileged write needs
  brightnessctl's logind/setuid helper. Called directly, argv-style — no
  `sh -c` wrapper, no `|| true`.
- **The exponent math moved into QML.** `percent = (raw/maxRaw) ^ (1/exponent)`
  on read, inverse on write, so the curve no longer depends on the installed
  brightnessctl having `-e` (0.5 does; it isn't ancient history). Two details
  that only show up at the dark end: a step is rounded to an integer raw value
  and can round back onto the current one (`bump()` forces ±1 so the wheel
  never feels dead), and the write is clamped to `minRaw: 1` because raw 0
  switches the panel off with nothing but another backlight write to undo it.
- **`raw` updates optimistically before the process runs**, so the label tracks
  the wheel instead of waiting for a fork + poll. A burst of wheel events
  coalesces: `Process.exec()` on a running `Process` isn't a queue, so the
  latest target is parked in `pendingRaw` and flushed `onExited`.
- **`bump()` takes signed wheel notches now** (`bump(1)`/`bump(-1)`), not
  brightnessctl delta strings like `"+5%"`/`"5%-"`; step size is service policy
  (`step: 0.05`), not the caller's.

Noctalia (`src/system/brightness_service.cpp`) was read for reference — it's
C++ now, so nothing was portable, but its device ranking was worth copying:
prefer any device over `acpi_video*` (a mirror of another device) and
`nvidia*` (often a stub), which is what `rank()` does.

## sysfs backlight *does* emit inotify — the old note was wrong

`services/BacklightService.qml` used to run a 1s `Timer` calling `reload()`,
on the documented belief (struck through above) that `sysfs_notify`/`poll(2)`
is invisible to inotify and `FileView.watchChanges` could therefore never fire
on `/sys/class/backlight/*/brightness`.

Noctalia's `src/system/brightness_service.cpp:945` does
`inotify_add_watch(<device>/brightness, IN_MODIFY)` in production, which was
reason enough to re-test rather than trust the note. Both halves confirmed on
this machine:

```
$ inotifywait -m -e modify /sys/class/backlight/dp_aux_backlight/brightness
  → MODIFY on every external brightnessctl write
```

and a standalone `qs -p` probe with `FileView { watchChanges: true }` on the
same path logged `FILECHANGED` + the new value for all three external changes,
immediately. The mechanism: `sysfs_notify()` reaches `kernfs_notify()`, which
raises a real `FS_MODIFY` through fsnotify — so inotify sees it like any other
file. **Fix:** `watchChanges: true` + `onFileChanged: reload()`, and
`pollTimer` deleted. `refresh()` survives only for the post-write resync in
`setProc.onExited`.

**Lesson (a repeat of the `pw-dump` one in `notes/privacy.md`):** an empirical
"confirmed" negative can encode the wrong mechanism. The original test really
did fail, but the write-up blamed sysfs-vs-inotify in general rather than
whatever actually went wrong in that one probe. A second implementation doing
the thing you wrote off as impossible is the cheapest possible signal to go
re-run the experiment.

