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

