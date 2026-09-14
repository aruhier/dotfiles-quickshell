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



## Toast entry and exit: staged like the OSD pill (2026-09-14)

A toast used to slide in fully drawn and slide back out, one spring, no
stages. It now arrives the way `shared/osd/OsdWindow.qml` does, by request —
"the same vibe of the OSD popup animations". **Read `notes/osd.md`'s staging
section first**; everything there about latches, overlap and aiming springs
past their target applies here unchanged, and only the differences are below.

**What slides in is the icon alone**, in a plate `2 * (padding +
iconHorizontalPadding) + iconSize` = 92px wide and `2 * padding + iconSize` =
84px tall, the card's insets mirrored so the icon sits dead centre of it. That
plate rests **centred on the card's width** and springs open out to it
sideways, the way the OSD's pill grows out of its own middle — but only
*downwards* vertically, for the reason two sections below. The card's whole
content — icon, text, actions, close
button — is laid out at the card's full width and position throughout and
merely *revealed* through the plate. Measured on DP-1 with a `grim` burst
(~11.9ms/frame, converted back to logical px), on a 414px-wide toast, each
column timed from its own first frame — the toast appearing, and the dismissal:

| stage | entry | exit |
|---|---|---|
| icon pill slides / leaves | 0 → 214ms visible alone | 229 → 450ms |
| plate opens / shuts | 214 → 714ms (peaks 430px) | 0 → 588ms, the last ~140 off-surface |
| bump past the resting line | ~11px slide, ~8px per edge opening | 52px wind-up, 112 → 229ms |
| settles | 414px wide by 714ms | off the surface at 450ms |

**Where the plate opens from took three passes, and the middle one is the
lesson.** In order:

| | plate | content | verdict |
|---|---|---|---|
| 1 | keeps its right edge, opens left | rides the left edge, travels the whole width | rejected |
| 2 | pinned at the icon's own corner, opens right and down | never moves | good, but not the OSD |
| 3 | centred on the width, opens out both ways | rides the left edge, travels half | shipped |

Pass 1 was reported as "it looks really different than the OSD animation, the
expand part is not smooth at all, and the notification slides fully expanded
instead of being limited to the icon". **The moving content was not what was
wrong with it** — the OSD's glyph is not stationary either, it rides its pill's
left edge and travels half the growth. What was wrong is that the icon
travelled the *whole* width, in the *same direction as the slide that had just
brought it in*, so there was no landing to see and the two stages read as one
long slide of a whole card. Centring halves that and splits it between two
edges moving apart, which reads as an opening rather than as more slide.

Pass 2 is still what the code is built on: the content keeps the card's full
size and position and is only *offset*, never relaid out, so **no text rewraps
and no row reflows however the plate moves**. Pass 3 changes where that offset
points, not what it is.

**Two things were needed to stop the opening reading as rough**, both
reported as "the expand needs to be smoother". First, `plateWidth` is
`Screens.snap()`ped: the plate's right edge carries a 1px border and a 10px
corner radius, while the reveal's scissor rect is whole device pixels whatever
the spring value is. Left fractional the two disagree by up to a pixel, so the
border renders at half intensity across two columns and the corner's
antialiasing crawls — at 240Hz that is a visibly shimmering edge. Second, the
detail's opacity ramp was moved from the second half of the opening
(`opened` 0.35 → 0.70) to its last quarter (0.72 → 1.0). The reveal is a hard
edge, so any text caught under it is cut mid-glyph and wipes in letter by
letter; held back this far, the text is still near-transparent while there is
anything left to cut and reaches full opacity as the plate settles. The OSD
needs neither — its detail is *anchored* to the pill's edges and squeezes
rather than being cut, which a card's wrapped text cannot do.

**That reveal is a `clip: true` on an Item, not a layer.** `clip` is a scissor
rect, so the text under it is not resampled — see `notes/text.md` for why a
`layer`/MultiEffect over text is not an option here. It is switched off
(`plateWidth < width`) once the plate is open, so the control-centre list,
which never sets `plateWidth`, carries no clip at all. The drop shadow's
MultiEffect stays *outside* the clipping item: its blur is drawn past the
plate's bounds and a clipping ancestor would cut it off.

**The plate opens into the gap the stack keeps from the screen edge.** A
window clips its contents, so the overshoot needs room on both sides and the
two sides are not symmetric:

| side | room | what needs it |
|---|---|---|
| left | `NotificationTheme.popupOvershoot`, 24px | the slide's ~11px bump *plus* the opening's ~8px, together; the shadow |
| right | the 10px edge gap, now inside the surface | the opening's ~8px, less whatever the slide is still leaning left |

**The two overshoots land on top of each other, and only on the left.** The
opening now starts while the slide is still settling (below), so the slide's
bump and the plate's peak coincide: measured, the left edge went 16.8px past
its resting place and the right edge 0.8px, from an opening that overshoots
8.4px on each edge and a slide leaning 10.8px left at that moment. They add on
one side and cancel on the other. It reads as the whole card lunging left and
settling, which is the gesture anyway, and it is why the left needs ~17px of
the 24 while the right sits inside its 10px gap with room to spare.

So `margins.right` is **0** and the resting gap is `anchors.rightMargin` on the
column instead — the same move `OsdWindow.qml` makes with `margins.bottom`.
That widens the surface past the stack on both sides, and a toast is
clickable, so the window needs `mask: Region { item: column }` or the slack
would swallow clicks meant for whatever is under it, the screen's own right
edge included. The OSD needs no such mask because nothing on it is clickable.

**`travel` is measured from the collapsed plate's own left edge**, not from
the card's: `width + edgeGap - collapsedX`. The pill rests centred, so half the
stack is already past the surface's right edge before it moves, and parking it
a whole stack-width away would spend most of the slide off screen — the visible
part fell from ~356ms to ~230 when this was still the card's full width.

**The card is driven by one number.** `NotificationPopupWindow` sets `openWidth`
(the spring) and `screen`, and `NotificationCard` derives `opened`, its whole
plate rect, the content's offset and the reveal's opacity from it, snapping
each edge to that output's pixel grid itself. Everything else — the staging,
the latches, the springs — stays in the window. The control centre sets none of
it: `openWidth` defaults to the card's width, so `opened` is 1 and every value
below collapses to the card's own rect.

**The opening is released while the pill is still arriving**, at
`travel * 0.15` rather than at the resting line. Both stages move the icon
leftwards, so with the opening held until the slide had settled the icon ran
fast, stalled, and ran fast again — a double pump, reported as wanting "a
smoother transition between the animations". Released a sixth of the travel
out, the opening's speed picks up while the slide is still decelerating and
the icon never slows in between. The OSD gets this for free: its two stages are
perpendicular, so they compose instead of interfering. The side effect is the
stacked overshoot above, and a *shorter* entry — 714ms against 809 — because
the later stage starts sooner, the same way `notes/osd.md`'s exit got shorter
when its stages were made to overlap.

**The exit's wind-up is the one place the OSD's own recipe does not carry
over**, and it took four passes to see why. Asked for as "lower the time
between the shrink and slide right, so that it looks more organic", then twice
more as "still a bit too much — the wait between animations is still a bit too
long". Measured against the shut's own start, tracking the icon (the thing the
eye follows) rather than the plate:

| | `narrowed` | hop aim | drop starts | gone | what the icon did |
|---|---|---|---|---|---|
| 1 | 0.2 | 1.5x | 404ms | 618ms | stood still for ~140ms |
| 2 | 0.35 | 2x | 297ms | 547ms | stood still for ~60ms |
| 3 | 0.5 | 4x, stiffer spring | 226ms | 381ms | stood still for ~35ms |
| 4 | 0.6 | 5x, `popupBump` 26 → 14 | 143ms | 321ms | never stopped |
| 5 | 0.6 | 9x, `popupBump` 14 → 24 | 143ms | 321ms | pulled ~4px back left |
| 6 | 0.6 | 5x, `popupBump` 24 → 52 | 166ms | 345ms | pulled ~19px back over ~48ms |

**The OSD's pill hops out of a plate that has already finished closing; a
toast's hops out of one that is still closing underneath it.** The icon rides
the plate's left edge, which — while the plate collapses towards the card's
centre — travels *rightwards* at up to ~0.9px/ms, against a hop pulling left.
Passes 1-6 are all attempts to tune around that cancellation, and none of them
can win: a hop slow enough to read as a wind-up is slower than the drift and
produces a dead stop; a hop fast enough to out-run the drift is then moving far
too fast to be turned around, and the turn reads as a yank ("the transition
between the bump and the slide looks weird and not smooth at all" — measured,
the icon went from -2.9 to +2.9px/frame in a single frame).

**Pass 7 removes the conflict instead of tuning it.** While a toast is leaving,
the plate shrinks onto *its own left edge* rather than onto the card's centre —
`NotificationCard.pinnedX`, latched by the delegate to whatever `plateX` was
when the exit began. The icon under it then does not move at all through the
shut, so the wind-up that follows is seen at its full size whatever speed it
runs at, and can be shaped for the turn rather than for out-running anything:

| | before the pin | after |
|---|---|---|
| icon during the shut | drifts ~100px right | still |
| hop aim | 5x past the bump, caught at full speed | 1.2x, eased into |
| spring under the hop | 95 (the drop's) | 600, critically damped |
| what the icon does | ~19px of the 52px bump | all 44px of it, decelerating |
| the turn | reversed at 769px/s | from near rest |

Measured after: the icon holds still while the plate collapses onto it, then
-4.0, -7.2, -8.0, -7.2, -7.2, -5.6, -4.8 px/frame, ~36ms at the apex, then
+7.2, +46, +31, +32, +34. That is the textbook anticipation shape — ease into
the extreme, hold, snap away — and the apex hold is the spring crawling the
last few px to its latch. It is worth having: the only way to remove it is to
catch the hop while it is still moving, which is exactly the yank this pass
fixed.

**Every closing spring was then stretched 1.15x**, by request ("make the whole
animations when closing the popup overall a bit slower"), with the usual knob —
`stiffness / 1.32`, `damping / 1.15`. Phases, integrated rather than captured:

| | hop starts | flip | shut done | gone |
|---|---|---|---|---|
| before | 96ms | 200ms | 504ms | 392ms |
| after | 112ms | 229ms | 588ms | 450ms |

The card is gone before the plate has finished shutting in both — the last
~140ms of the collapse happens off the surface, which is free.

One thing from those passes is worth keeping even now: **the time a hop costs
depends on the ratio `popupBump / aim`, not on `popupBump`** — a critically
damped spring covers a *fraction* of its target in a fixed multiple of `1/ωn`.
Size and duration are independent knobs as long as the aim is scaled with the
bump. What that bought was a bigger bump for free; what it could not buy was a
bump that survived the drift.

**The slide spring is tuned three ways, not two.** The entry is soft and under
damped (58 / 8.4, ζ ≈ 0.71); the wind-up is stiff and critically damped
(455 / 32.9) so it covers its distance quickly *and* arrives, since a soft hop
has to be aimed far past to move at all and is then moving too fast to turn;
and the drop goes back to something soft enough not to snatch (72 / 13.4). One
spring, three phases, switched on `closing` and `wound`. The plate's own spring
splits the same way — 122 / 11.5 opening, 92 / 15.7 shutting.

**The slide spring is softer than the OSD's** — stiffness 58/damping 9.1
against 136/12.3, same ζ ≈ 0.77. Not a taste difference: the OSD's pill rises
through 187px and is visible for all of it, while a toast's icon is off the
surface for the first four fifths of its ~425px travel. At the OSD's own
constants the pill was on screen for ~103ms of a 258ms slide, which is not
long enough to register as a stage at all; here it is ~357ms, which reads like
the OSD's 245ms rise.

**Both springs were then slowed, by request, with the knob `notes/osd.md`
documents**: `stiffness / 1.21`, `damping / 1.1`, which stretches a spring's
durations by 1.1 and leaves its damping ratio where it was — scale the pair,
never the stiffness alone. Everything went through it once ("I would make the
animation (overall) slightly slower"), and the plate's spring twice, the second
pass on its own ("you still need to make the expand/shrink a bit slower /
smoother"). That is what puts the slide at 58 stiffness and the plate at
122, rather than the OSD's 136 and 215.

**Then the bumps were opened up**, by request ("make the animation a bit more
fun, like the OSD does — a bigger bump, for example"): damping 9.1 → 8.4 on the
slide (ζ 0.77 → 0.71, an ~11px bump) and 12.4 → 11.5 on the plate (ζ 0.73 →
0.67, ~8px on each edge). The shut stays damped past 1, and the slide's exit
is both stiffer and shorter than its entry — 95/15.4 against 58/8.4, same ζ —
since the wind-up and the drop both ride it and at the entry's stiffness the
hop alone took ~140ms to reach its latch however early it was released. The plate's is as far as it goes: at ζ 0.64 the right edge
would reach past the screen edge, and the gap it opens into is only 10px.

**The height opens off the width's progress, not its own spring.** One
`opened` drives `plateWidth`, `plateHeight` and `plateY`, so the plate reaches
its full size on one curve; two springs over the same gesture would land its
two edges at different moments. The height is taken from the *clamped*
progress where the width is not — the width is free to spring past the card
and settle back, but a bottom edge overshooting does it into the toast below.
First shipped as width-only, which was wrong: reported as "the expand also
needs to work on the height, right now it's just width".

**Only the width is centred. Vertically the plate stays where the icon is and
grows downwards**, and the content never moves on that axis at all. Centring
both axes was tried and rejected on sight — "it looks strange, I prefer not to
have this drift": sideways the content riding the plate reads as the icon
pulling the card open, but the same thing vertically reads as the text sliding
up into place under a plate that is opening around it, which is two motions
disagreeing rather than one gesture.

So `plateY` is `collapsedY * (1 - opened)` with `collapsedY` =
`(contentRow.height - iconSize) / 2`, and the content is offset by `-plateY` to
cancel it. `collapsedY` is 0 on every toast whose text is shorter than the
64px icon — which is most of them, and every one with action buttons, since
the actions sit below that row rather than in it. It is there for the ones
where it isn't: the icon is centred in `contentRow`, a three-line body pushes
that row past the icon's own height, and a plate pinned to the card's top
corner would then cut the icon off. Verified against both shapes, since on a
2-line toast `collapsedY` is 0 and hides the bug.

**The row keeps the card's full height throughout**, so the stack reserves the
space a collapsed toast will grow into rather than growing with it. That leaves
a gap under a pill that has toasts below it, which in practice only shows
during an exit: a new toast is appended at the bottom of the stack, so nothing
sits under it while it opens. The alternative costs much more than it looks —
the window's `implicitHeight` is the column's, so an animating row height
reconfigures the layer surface every frame, which is the thing
`notes/osd.md` moved the OSD's whole resting gap inside its surface to avoid.

**`popupBump` is 16px** against the OSD's 18, and the entry's bump is ~8px
against ~10 — same ratio, scaled to a surface that moves sideways across a
wider span. Both are latched exactly as `notes/osd.md` describes, with
`narrowed` at `opened <= 0.2` so the wind-up starts while the plate is still
visibly shutting.

**The gesture itself now lives in `DismissSlide.qml`**, shared with the control
centre (see the section below) — one spring, because the exit has to pick up
wherever the arrival left the item, so the toast's entry rides it too via
`playEntry`. The window keeps only what is specific to a toast: the `narrowed`
gate before `start()`, `closeX`, and the plate spring the latches release. The
entry tuning (58 / 8.4) is `DismissSlide`'s default because the toast is the
only caller that plays one; the exit's four constants had been copied verbatim
into both files before this.

**Two things the per-delegate version does that the OSD does not.** The
latches live on the delegate rather than on the window, since every toast
stages independently — two arriving 300ms apart were verified overlapping,
one opening while the next slides in. And the exit's last stage ends by
*destroying* the delegate: the drop is aimed 1.5x past the surface, parked
with `snapTo()` the moment the card clears it, and the resulting
`onRunningChanged` is what calls `removeDisplayPopup()`. That runs inside the
spring's own frame callback, which was already true before this change.


## Dismissing from the control centre: the toast's exit, minus the plate (2026-09-14)

A row dismissed in the panel used to vanish on the frame the model changed. It
now leaves with the gesture a toast does, by request — "when I close a
notification there, it slides right […] a small bump to the left before, the
same way we have for notifications popups". `shared/notifications/DismissSlide.qml`
is that gesture on its own: the wind-up and the drop from the toast's exit,
with none of the plate staging around them, so there are two stages and one
latch rather than four and three. The caller applies `value` as a `Translate`
and does the dismissing from `finished`.

The springs are the toast's — 455/32.9 critically damped under the wind-up,
72/13.4 under the drop, aimed `1.2x` past the bump and `1.5x` past the edge —
and since 2026-09-14 they are literally the same code rather than a copy of it:
the toast's exit was folded into this file, which grew an optional entry phase
for it. A panel row plays none and starts at rest. Measured on DP-1 with a `grim` burst (~20ms/frame, converted back to
logical px), tracking the icon, timed from the frame the click landed on:

| stage | control centre | a toast, for comparison |
|---|---|---|
| wind-up | 0 → 115ms, 18px left | 112 → 229ms, ~19px of a 52px bump |
| flip | ~135ms | 229ms |
| off the surface | ~345ms | 450ms |

**`popupBump` is 52 and this is 18, and they are the same size on screen.** A
toast's hop runs under a plate that is still collapsing rightwards and loses
most of itself to that drift; nothing moves under a panel row, so the whole of
`listDismissBump` is seen. Measured: 295.2 → 277.6px on the row, 18.4px on a
card inside an expanded group.

**The dismissal is deferred to the end of the gesture, not played after it.**
The list's model is `NotificationService.notificationGroups`, a plain JS array,
so *any* change to it resets the view and recreates every delegate — a card
mid-flight would be destroyed and replaced at rest. So every close path now
runs the gesture first and dismisses from `finished`: the card's own close
button stops calling `NotificationService.dismiss()` and emits
`dismissRequested` instead (a toast still dismisses outright — its exit is
staged by `NotificationPopupWindow`), the group's two close-all buttons and the
panel's Delete key go through `NotificationGroupCard.dismiss()`, and the panel
reaches its selected row with `itemAtIndex()` rather than calling the service,
falling back to the old direct call for a row too far out of view to have a
delegate.

**Two things follow from dismissing late, and both are handled in
`NotificationService.dismissLater()`.** It is called from inside a spring's own
frame callback, and mutating the model there regenerates every delegate
reentrantly — the shape that already segfaulted `QQuickRepeater::regenerate()`
once (see the popup section above), hence the `Qt.callLater`. And a delegate
can still be destroyed mid-gesture, by a notification arriving in the ~345ms
the gesture takes; `Component.onDestruction` re-submits the same wrappers so
the click is not silently lost. That is why the function checks each wrapper is
still in `notifications` before dismissing rather than just calling
`dismiss()`: a wrapper dropped in the meantime is a destroyed QObject, which is
not null from JS and throws on property access. Verified live — dismissing a
row and firing a `notify-send` 150ms into the gesture still removed it. What is
*not* preserved is the animation: the replacement delegate appears at rest and
the row disappears a frame later without sliding.

**Who slides is the row, except inside an expanded group.** A single-notification
row and a collapsed stack's close-all move the whole delegate; one card of an
expanded group moves alone and the header and its siblings stay put, since only
that notification is going. Both use the same `exitTravel`, which clears the
list's clip rather than the screen edge — the `ListView` bounds are the panel's
16px padding short of the edge, so a leaving card is cut there rather than at
the screen's edge. Checked on a burst: dark card on dark panel over the ~6ms
the cut is in flight, nothing reads.

**The gap the row leaves closes instantly, as the toast stack's does.** A
height collapse animating after the slide was considered and left out: the eye
is following the card off the edge by then, and an animating row height
reconfigures nothing here but does put every row below it on a spring for a
gesture that is already over.

**`enabled: false` on whatever is leaving**, rather than guarding each
`MouseArea` and button — one line, and it matches a closing toast going inert
(`interactive: !closing`). The hover flags drop with it, so the close button
fades out over the slide exactly as a toast's does.


## Toasts read as glass, like the OSD (2026-09-14)

Reported as "the popups should be a bit more rounded, and look more like the
OSD in terms of transparency". The rounding is one number
(`NotificationTheme.popupRadius`, 18 against a list card's 10, set on the card
from `NotificationPopupWindow.qml` so nothing in the control centre moves).
The transparency was not a number at all — **the toast's plate was being
composited twice**, and the second pass is what made it opaque.

`NotificationCard.qml` paints its plate as a `Rectangle` that is also the
`MultiEffect` source for the drop shadow. A MultiEffect source is *not*
excluded from ordinary scene painting the way a `ShaderEffectSource` with
`hideSource` is: the rectangle was drawn once by the scene graph and once more
through the effect, and two 0.89 alphas compound to 0.99. Measured over a
white window on DP-1, plate interior against a `(245,242,238)` backdrop:

| | over dark desktop | over white window | effective alpha |
|---|---|---|---|
| toast, plate drawn twice | (40,40,40) | (43,43,43) | ~0.99 |
| toast, plate drawn once | (40,40,40) | (71,70,69) | 0.89 |
| OSD pill (never had the effect) | (43,43,44) | ~(59,59,58) | 0.89 |

`bgFloating` then settled at **0.94**, not the 0.89 the OSD had been carrying:
0.89 reads as glass over the desktop but leaves the backdrop's own text
legible enough through a toast over a white window to compete with the
summary. Over white the plate goes 71 → 65 at 0.92 → 60 at 0.94, while over
the dark desktop all three sit within a level of each other — the whole knob
is spent on the bright case. Anything past this stops showing the blur at all
and the surface reads as a flat chip again.

The give-away was that the toast barely moved between a dark backdrop and a
white one, where the OSD moved by ~16 levels. Dropping the alpha to 0.4 to
test showed 115 where a single pass predicts 164 and two passes predict 115 —
which is what identified the double pass rather than the blur or the shadow.

Fixed with `visible: !card.floating` on the plate: the effect then paints it
once, shadow and all. **Only for a toast.** A control-centre card sits on the
panel's own plate rather than on the desktop, so undoing the compounding there
would lighten every row in the list — out of scope for this change, and still
true if it is ever wanted.

`bgFloating` went 0.875 → 0.94 and `Theme.osdOpacity` was deleted, so the
toasts and the OSD are now literally the same colour (see notes/osd.md).

**The other half was a missing layerrule.** `quickshell-notifications` had no
`blur` rule where `quickshell-osd` and `quickshell-notification-center` both
do, so once the plate was genuinely translucent the window behind it showed
through *sharp* — legible text under the toast, which is worse than opaque.
Added to `~/dotfiles/hypr/conf/rules.lua` with the OSD's own threshold:

```lua
hl.layer_rule({ match = { namespace = "quickshell-notifications" }, blur = true, ignore_alpha = 0.8 })
```

`ignore_alpha` has to stay below the plate's alpha and above the shadow's:
0.8 blurs the plate and leaves the shadow's halo alone. Verified by removing
the rule and re-shooting — same pixel values either way (Hyprland's blur
brightness cancels out over a flat backdrop), the difference is entirely
whether the bleed-through is sharp or smeared, so **measure this one by eye,
not by sampling**.

Not touched, and a candidate if the entry ever looks doubled:
`quickshell-notifications` has no `no_anim` rule either, so Hyprland still
fades the surface in as the first toast's own spring plays. The window only
maps and unmaps at the ends of a burst, so it is one fade per stack rather
than per toast.
