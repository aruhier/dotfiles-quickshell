# Verification method

## How to take a screenshot for visual verification

Screenshot a specific output with `grim` (get geometry first, since `-o`
and `-g` are mutually exclusive):

```sh
hyprctl monitors -j
grim -g "2560,0 3840x28" out.png
```

If cropping a full-output screenshot in stages with ImageMagick, add
`+repage` after each `-crop` — otherwise the canvas offset carries over and
a second crop measures from the original image's coordinates.

Monitor layout is machine-specific — re-check with `hyprctl monitors -j`
rather than trusting old notes. `DP-1` is the output with tray/privacy/weather.

## Full visual re-verification (2026-08-29, two passes)

**First pass** missed a real bug: per-glyph pixel-diffing (bell,
volume-mute, clock text) all matched, but nobody measured the *aggregate*
width of `modules-right`. Caught only by a user follow-up.

**Second pass** found it: `Tray.qml` hardcoded `spacing: 8` and 16px icons,
against an intended 14px icons with 20px spacing — more than double. Fixed
both values.

**Lesson:** per-glyph diffing isn't sufficient — it can't catch a spacing
deficit spread evenly across many small gaps. Check the *aggregate* group
width first (sample where a column's color transitions between bar/group
background), before zooming into individual icons.

**Follow-up fix (2026-08-30):** `Tray.qml` was still missing the shared
6px-each-side padding rule that every module gets. Fixed by widening
`implicitWidth` to `row.implicitWidth + 12`.

**Scaling note:** `DP-1` runs at Hyprland `scale: 1.25` — `grim -g`
geometry is logical px, but the output PNG is physical px, so raw
pixel-count comparisons need the scale factor divided back out.

**Capture note:** always grab a few px of vertical slack past the nominal
bar height — an exact-height crop can appear to be missing a bottom border
at fractional scale, where the last row lands on a partial device pixel.
(An earlier version of this note blamed `margins.bottom: 1` for making the
window 1px taller; it doesn't — the surface is exactly `barHeight +
barBorderHeight`, and the margin grows the *exclusive zone* by 1px instead,
`hyprctl monitors` reserved `[0,26,0,0]` against a 25px layer. See Bar.qml.)

**Working method:** capture the same geometry, diff the aggregate
group-edge position first, then crop matching sub-regions to compare
individual icons at zoom. For gap measurement within a crop, a
brightness-threshold column scan (cluster non-background columns into
per-glyph segments) beats raw pixel diffing, since antialiasing produces
false positives pixel-by-pixel.


## Probing Quickshell state without disturbing the running bar

`qs -p <dir>` on a throwaway `shell.qml` reads live service state without
touching the real config, but **`console.log` is DEBUG on the `qml`
category and is invisible by default**:

```sh
qs -p /tmp/probe --no-color --log-rules 'qml=true' 2>&1 | grep 'DEBUG qml:'
```

Without the flag the probe runs and prints nothing at all, which reads
exactly like "the timers never fired". Logs also land in
`/run/user/1000/quickshell/by-id/*/log.qslog`, readable with `qs log`.

Worth doing: have the probe build the code under test by extracting it from
the real source file rather than pasting a copy, so what's measured can't
drift from what ships. An A/B probe running the old and new logic side by
side over the same live graph is what turned "this looks wrong" into
`2 rows → 1 row`.


## Measuring CPU, frames, and idle cost

These traps each invalidated at least one full measurement round.

**Wait ~6s after every edit before sampling.** Quickshell hot-reloads on file
change, so A/B testing is edit-file → measure on the same PID — but a reload
burns a few hundred ms rebuilding the scene. An early pass that sampled
immediately produced a per-module CPU table that was pure reload noise; the tell
was results alternating hot/cold with loop order. Note also that `touch` does
**not** trigger a reload — the contents have to actually change.

**`strace -f -c` is the crispest idle check**: ~90 `sendmsg`/s when rendering
every frame, none at all when truly idle. If `kernel.yama.ptrace_scope = 1`
blocks attaching to a running `qs`, the privilege-free substitute is per-thread
**voluntary context switches** out of `/proc/<pid>/task/*/status`, sampled
twice. A constant ~1.2 wakeups per vblank on an output is the signature of
"rendering every frame", and it is a *better* signal than `%CPU`: it says which
windows are rendering and at what rate, where `%CPU` only says "high".

**`QSG_RENDER_TIMING` output is block-buffered when redirected to a file.** It
goes to stdout through quickshell's own message handler, so a short 2-3s
measurement phase can end entirely inside the 4KB buffer and read as "zero
frames". Launch under `stdbuf -o0 -e0`, append to one log, and slice phases by
`stat -c %s` offsets. Truncating the log mid-run does not work either — the
process keeps its old file offset.

**Know what per-frame instrumentation counts.** A `console.warn` in
`FrameSpring`'s `onValueChanged` fires once per *integration sub-step* (4 per
frame at 16ms, ~1-2 at 4ms), not once per frame — which makes 60Hz look like
250Hz.

**`pkill -f 'qs -p'` can kill its own invoking shell.** `-f` matches the full
command line of every process, including the shell running the `pkill` — whose
argv literally contains `qs -p`, since that is the command being run. Several
kill attempts died silently with exit 144 and no output this way. Use an exact
name match instead: `pkill -x qs` / `pgrep -x qs`.

**Bisect by layout.** `shell.qml`'s `mainLayout`/`defaultLayout` arrays are the
natural bisection knob for "which module is burning CPU": empty both, reload,
then add modules back in halves. That separates a module from the
always-instantiated shared windows (`NotificationPopupWindow`,
`NotificationCenterPanel`, `OsdWindow`) in about four seconds of editing.
