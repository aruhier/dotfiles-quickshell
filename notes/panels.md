# Panels and popups

## Click-triggered popups: resolved differently than predicted (2026-09-02 → 2026-09-03)

`shared/popup/PopupCoordinator.qml` only knows one dismissal model: a
single hover-triggered `activeOwner` that gets closed when another hover
popup activates. That's correct for what exists today (Clock's calendar,
Weather's forecast — both cursor-hover popups, and there's only one
cursor, hence a plain global singleton with no per-screen tracking).

DankMaterialShell's equivalent (`Common/PopoutManager.qml`, compared
against ours on request) additionally distinguishes hover-opens from
click-opens: a click sets `hoverDismissEnabled = false` to *pin* the
popout open (it survives the cursor leaving), while a hover keeps it
auto-dismissing, and clicking the same trigger again toggles it closed.

The bar's first click-triggered popup arrived the next day: the
notification control-center panel (see the dated section below). It did
**not** end up extending `PopupCoordinator` — there's only one such panel
(not an open-ended set of click-popups needing mutual exclusion like the
hover ones), so `NotificationCenterPanel.qml` just gates its own
`visible` off one singleton bool (`NotificationService.centerOpen`),
toggled by the bar indicator's click handler. Click-outside-to-close is
solved by anchoring that one `PanelWindow` to all 4 screen edges with an
outer full-window `MouseArea` behind the actual (right-docked) panel
content, rather than by teaching `PopupCoordinator` a "pinned" concept.
**If a second, independent click-triggered popup shows up later**,
*then* it's worth generalizing — right now there's nothing to
generalize from except this one case.


## Control-center panel now opens on the clicked screen, not always the main screen (2026-09-03)

`NotificationCenterPanel.qml` is still one shared window process-wide (per
the click-triggered-popups section above — there's only one such panel, so
no per-screen instantiation), but it used to be hardcoded to `root.mainScreen`
in `shell.qml`, so clicking the indicator on a non-`DP-1` output opened the
panel on `DP-1` anyway.

**Fix:** `NotificationCenter.qml` (the bar indicator) now takes a `required
property var screen` — `Bar.qml` binds it to `barWindow.modelData`, same
pattern `Workspaces.qml` already used for its `screenName` — and passes it
to `NotificationService.toggleCenter(screen)`. The service stores it as
`centerScreen` (a real `ShellScreen`, not a name) and `shell.qml` binds the
panel's `screen: NotificationService.centerScreen || root.mainScreen`,
falling back to the main screen only before the first-ever click.
`toggleCenter` closes the panel if it's already open *on the screen that was
clicked*, otherwise moves it to that screen and (re)opens it — clicking a
different screen's indicator retargets the panel rather than just closing
whatever screen it happened to be open on.

Verified by comparing against DankMaterialShell's `PopoutManager`/
`NotificationCenterPopout.qml`: it uses the exact same shape (single shared
popout, `property var triggerScreen: null`, `screen: triggerScreen`, set
from `barWindow.screen` at click time) — including a `present()` doc comment
that calls out "re-open without toggling the flag (used when retargeting to
another monitor)", confirming live `screen` reassignment on an
already-shared window is the intended, supported pattern here, not a hack.

Confirmed empirically since no synthetic-click tool was available on this
machine (no ydotool/wlrctl): temporarily drove
`NotificationService.toggleCenter()` from a startup `Timer` targeting a
specific non-main screen, screenshotted, and checked `hyprctl layers -j` —
the `quickshell-notification-center` layer surface appeared only on the
targeted screen, never on `DP-1`.

**A transparent `PanelWindow` whose visible edge comes from a child
`Rectangle`, not the window's own `color`, can leave the true last physical
column of a flush screen edge transparent at a fractional Hyprland `scale`
(2026-09-03).** `NotificationCenterPanel.qml`'s panel is flush against
DP-1's right edge (`scale: 1.25`); with `anchors.rightMargin: 0` the panel
rectangle's own logical geometry was exact (`panel.x + panel.width ===
screen.width`, confirmed via a temporary debug `Timer` logging those
values), yet a `grim`-captured screenshot showed the single rightmost
physical column still showing desktop background, not the panel. `Bar.qml`,
anchored flush against the same edge on the same output, does **not** show
this — its background is the `PanelWindow`'s own `color` (an opaque native
window background), not a child scene-graph item. Disabling `antialiasing`
on the Rectangle (the fix for the unrelated seam bug in `Workspaces.qml`,
see `notes/rendering.md`) made no difference, ruling out AA-shader coverage
as the cause —
this is the compositor's fractional-scale buffer upscaling not reliably
covering its own edge texel when a child item's paint has to carry the
window's only opaque content. **Fix:** `anchors.rightMargin: -2` — a
deliberate 2px overscan past the window's true edge. Safe because that
side has no corner radius (square) and sits past the actual screen edge,
so the compositor clips it; verified across the full panel height that
this fully closes the gap (pixel-sampled at 7 different rows) with no
other visible change. Note this parallels `Bar.qml`'s existing
`margins.bottom: 1` overscan-past-the-visible-edge pattern for a different
reason (that one avoids a 1px-tall miscrop when screenshotting, not a
render gap) — deliberate small overscans past a true edge are an
established, safe pattern in this codebase specifically because content
past the true output boundary is always compositor-clipped for free.

**Why a fixed `-2` (not scale-derived) is the right call, not a magic
number tuned to one machine's `1.25`:** the failure mode is a sub-1-physical-
-pixel rounding gap, so the minimum overscan needed shrinks as scale grows
(a 1-physical-px gap needs ~0.8 logical px of cover at `scale: 1.25`, ~0.5
at `scale: 2`, etc.) — `2` logical px is comfortably above worst case at
every scale `>= 1`, and Hyprland has no sub-1 scale. At integer scale the
bug doesn't occur at all (no buffer resampling needed), so overscanning
there is pure insurance, not a fix for anything real — and since the
overscanned pixels are always past the true edge and always
compositor-clipped, adding unnecessary insurance at integer scale costs
nothing. Confirmed empirically, not just reasoned: opened the same panel
(via a temporary debug `Timer` retargeting `NotificationService.centerScreen`)
on `DP-2`/`HDMI-A-1` (`scale: 1`, this machine's other two outputs) with the
`-2` fix already in place — right edge pixel-sampled at 5 rows, panel
background reaches the true last column cleanly, no gap, no seam, no
overscan artifact. So the fix is scale-independent by construction (any
`scale >= 1`, gap always < 1 logical px, `-2` always exceeds it), not just
untested outside the one value this bug happened to be caught on.


## Control-center panel slide animation, and a same-tick visibility race (2026-09-03)

Added a spring slide in/out on the right edge for
`NotificationCenterPanel.qml`: `panel.anchors.rightMargin` animates between
its resting `-2` and fully off-screen (`-panel.width - 2`) via `Behavior on
anchors.rightMargin { SpringAnimation { spring: Theme.springSpring;
damping: Theme.springDamping; ... } }`, the same shared spring every
module's `implicitWidth` already eases through.

**The window has to stay mapped for the whole close animation, not just
while `NotificationService.centerOpen` is true** — unmapping the instant
`centerOpen` flips false would cut the slide off after one frame (nothing
left to animate once the layer surface is gone). Fix: `panelWindow.visible:
open || closing`, where `open` mirrors `centerOpen` and `closing` is set
true the moment it goes false, then cleared by the `SpringAnimation`'s own
`onRunningChanged` once it actually finishes.

**A same-tick QML property write does not batch — each write fires its
change notification, and re-evaluates every dependent binding,
immediately, before the next statement runs.** The first version of the
above set `open` and `closing` in a single `Connections.onCenterOpenChanged`
handler, in this order:
```js
panelWindow.open = NotificationService.centerOpen;  // -> false
if (!NotificationService.centerOpen)
    panelWindow.closing = true;
```
This looks atomic (one handler, no `await`/timer in between) but isn't:
writing `open = false` immediately re-evaluates `visible: open || closing`
using the *current* (still `false`) `closing`, so `visible` goes false —
unmapping the window — for the single JS tick before the next line sets
`closing = true` and remaps it. User-visible result: "the panel disappears
for a frame, then reappears and slides." **Fix: order the writes so the
disjunction is never false at any intermediate point** — set `closing =
true` *before* `open = false`. A single `onRunningChanged`/`Date.now()`
console.warn on each `visible` change confirmed the exact mechanism: two
transitions logged at the identical millisecond (`false` then `true`)
before the reorder, one clean transition per open/close after it.

**Lesson, distinct from the ordering bug above: don't trust a live
hot-reloaded instance to validate a same-tick timing fix.** Repeated
edit-and-reload cycles against one long-running `qs -p ./` process can
leave stale component instances alive alongside the new one; both react to
the same singleton signal and both log, which reproduces what looks like
the *exact same* race even after the real fix lands. Only a full process
restart (kill + relaunch) gave a trustworthy before/after comparison here.

**Lesson: don't screenshot-diagnose animations on this machine without
checking what's behind the target window first.** A `grim` capture of the
panel's screen region, taken when the panel happened to already be fully
closed, captured whatever normally fills that space on DP-1 instead —
which turned out to be the user's email client, not blank desktop.
Stills can't show motion anyway (a user correction mid-session:
"you can't see animation with screenshot") — for this class of bug
(same-tick property races, animation curves), a per-frame `console.warn`
of the specific property values, diffed against a known-good and
known-bad ordering, is both safer and more diagnostic than screenshots.


## The panel's slide is staged, like the OSD pill and the toasts (2026-09-14)

The slide used to be one near critically damped spring each way (160 / 18,
ζ ≈ 0.92): in, it ran up to the screen edge and stopped dead on it; out, it
simply left. It is now the shell's staged gesture — **four stages on one
spring, two latches, every stage critically damped**: sweep in, ease into a
bump past the resting place, settle back out of it, then on the way out wind up
*onto* the screen before dropping off the edge. Requested in three passes: "a
bump overshoot comparable to what the notification popups do (without the
expand/shrink thing)", then "the bump looks too mecanical", then "I would also
like to have the bump to the left before sliding right, when closing the panel
— same way that for the notifications popups or the OSD".

**Read `notes/osd.md`'s staging section first**; the latches, the aiming past a
target and the overlap all work there exactly as they do here.

### Why staged, and not one under damped spring

The first two passes used a single under damped spring (ζ ≈ 0.71) and the bump
was its overshoot. That is what got reported as mechanical, and a `grim` burst
says why. Measured on DP-1 (~12.5ms per sample, logical px, tracking the
panel's left edge):

| | one under damped spring | staged |
|---|---|---|
| crosses the resting line | ~190ms | ~205ms |
| bump | 18.0px at ~320ms | 18.5px at ~306ms |
| return to the resting line | **~250ms, flat ~80px/s** | **~150ms, eased** |
| fastest step of the return | 1.6px per sample | 2.4px per sample |
| total | ~570ms | ~470ms |

A spring aimed *at* its resting place crosses it at full speed, so the
overshoot is the fast half of a sine and the return is its slow half — a
near-linear crawl that reads as a mechanism. A spring aimed *past* the bump and
caught there by a latch arrives at the extreme slowly, and is released from
near rest into a second spring that eases back. Ease in, hold, release: the
anticipation shape, and the same one the toast's wind-up gets from the same
trick. It is also why the counter-oscillation is gone — nothing here is under
damped any more, the bump is geometry rather than ringing.

The aim is `1.2x` the bump, as everywhere else in this shell. The coast past
the latch is only 0.1px, because by then the spring has nearly stopped.

### The stages

| stage | gate | spring | what it does |
|---|---|---|---|
| sweep in | opening, `!bumped` | 227 / 23.3 | 500px of travel, aimed at `resting + bump * 1.2` |
| settle | opening, `bumped` | 345 / 28.8 | eases the 18px bump back out |
| wind-up | closing, `!wound` | 455 / 32.9 | 24px onto the screen, aimed `1.2x` past |
| drop | closing, `wound` | 72 / 13.4 | off the edge, aimed `1.5x` past it |

**The opening pair were then slowed 15%**, by request, with the usual knob —
`stiffness / 1.15²`, `damping / 1.15` — from 300 / 26.8 and 457 / 33.1. The
closing pair were left alone. Measured on a burst either side of the change,
which is also a check that the knob does what it claims: the bump survives it,
being a property of the damping ratio rather than of the pace.

| | before | after | ratio |
|---|---|---|---|
| reaches the resting line | 211ms | 250ms | 1.19 |
| bump | 18.5px at 306ms | 17.7px at 363ms | 1.19 |
| settled | 519ms | 621ms | 1.20 |

(Measured ratios run a little over the 1.15 asked for: one sample is ~12.5ms,
which is 4-6% of these durations.)

The exit pair are the toasts' own numbers (`DismissSlide.qml`), which is what
"the same way as the popups" means here. Measured, again on a burst: the
wind-up peaks 23px left of rest ~100ms in, decelerating into it, then flips and
clears the screen ~210ms later — against the toast's 115ms / 450ms, on 500px of
travel rather than 265.

**Where it lives.** `ControlCenterSlide.qml`, next to the gesture it is not
(below). The panel hands it where it rests and where it is clear of the screen
and binds `margin`; the staging, both latches, the tuning and the landing are
the component's. It was inline on the panel's background Rectangle first, which
put ten properties and the whole four-stage handler on an object whose job is
to be a plate.

**Why not `DismissSlide.qml` itself.** It drives a `Translate` from a resting
place it assumes the item is sitting at, and it owns its own spring. This panel
can be closed *while it is still arriving*, and one spring driving the margin
picks the panel up wherever it actually is — two would have to hand over a
position and a velocity, or the panel would jump. The OSD makes the same call
for the same reason and stages itself in `OsdWindow.qml`.

**The bump sizes are pixels, not a damping ratio, and the two differ.** 18px
arriving, 24px winding up — the OSD's ratio, where a wind-up is the whole
gesture rather than the tail of one. Nothing moves underneath either, so both
read at full size, like a control-centre row's 18 and unlike a toast's 52.

### The bump must not open a gap at the screen edge

First shipped bumping off the old resting `-2`, which put ~9px of desktop and
the panel's square right edge (with its 1px `borderSubtle` outline) on screen
for the ~300ms around the peak. Reported as "a bit weird […] the notification
panel needs to be wider than what it really is so that it doesn't show that
it's out of the screen", and that is the fix:
`NotificationCenterPanel.qml`'s `overscan`, 22px of panel drawn *past* the right
edge, with the resting margin at `-overscan` rather than `-2`. The bump pulls
that slack in and never reaches the panel's own edge — verified on the burst:
once the panel is on screen, the screen-edge column is never desktop in any
frame. The slack is free, being compositor-clipped either way; it is what has
to grow if `ControlCenterSlide.qml`'s `bump` (`NotificationTheme.bump`) ever does. Same trick as the fractional-scale
edge column in the section above, sized for a different job, and it subsumes
it: one overscan now, not two.

What that makes the gesture, precisely: the panel's width never changes and its
right edge stays off screen throughout, so what reads is the *left* edge
lunging past where it will rest and easing back, with the contents riding it.
Nothing relayouts during the bump — only the Rectangle's x moves.

Three consequences of drawing it wider:

- **The width is snapped in two parts and added** — `Screens.snap(width) +
  Screens.snap(overscan)` — not snapped as a sum. The panel is right-anchored,
  so the left edge lands at `width - overscan`; snapping the sum alone would
  leave that difference off the device pixel grid, which is what the 1px border
  and the panel's own outline are snapped for in the first place.
- **The contents fill the visible part, not the overscan**
  (`anchors.rightMargin: panel.edgeOverscan` on the sibling Item that holds
  them). Filling the whole Rectangle would measure the layout's 16px padding
  from an edge that is 22px off screen, taking every row's right inset off the
  visible panel entirely.
- **The panel reads 2px wider than it used to**, 500 rather than 498: the old
  `-2` came out of the visible width, and the overscan is now separate from it.
  The contents gain those 2px back as padding, since they used to be offset
  into the overscan too.

### It moved the list's text off the logical grid

Widening the panel shifted its contents 1.6px, which put every card in the list
on a fractional *logical* x and fringed all of their text — the panel's own
header, 26.4px to the left of them, stayed crisp. Reported as "the text in
notifications in the panel has some fringe/artifacts". The list's horizontal
insets are now solved against where the cards actually land
(`Screens.snapTextInset()`), off `panel.listEdge` — the panel's *resting*
position, never its live x, since re-solving mid-slide would walk the list
sideways inside the panel. The mechanism, the measurement, and why neither
`snap()` nor a coarser rounding of the inset is enough in front of text, are in
`notes/text.md`.

### Dead end: snapping the slide to the device pixel grid

"Rough" was first read as a rendering artifact and the spring's value was
snapped per frame — the panel is the drop shadow's `source`, so it is drawn
from a layer texture that resamples when it lands off-grid, and the glyphs over
it are snapped to whole pixels while the plate under them is not. The burst
killed it: at 1.25 scale the grid is 0.8px, and the slow tail of the gesture
advances *one* grid step every ~10ms, so a 240Hz output shows the same position
for two or three frames and then a jump. Snapping traded a sub-pixel blur on a
moving object, which the eye does not resolve, for visible stepping, which it
does. Resting offsets are still snapped — those are what the border and the
text need; motion between them is not.

**Method note:** `grim -g` takes *logical* coordinates in the compositor's
layout — DP-1 sits at x=2560, so its right edge is x=5632, not 3840 — and
writes *physical* pixels, so the image is 1.25x the region. A burst of
one-pixel-tall captures across the edge's travel (~12.5ms apart, timestamped in
the filename), differenced against a reference row of the closed state, gives
the whole curve. Trigger the gesture from inside the capture loop; `seq -w 0 90`
pads to *two* digits, and a trigger keyed on `"003"` never fires.
