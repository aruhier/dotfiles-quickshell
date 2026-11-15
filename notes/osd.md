# OSD

## Native OSD, replacing swayosd (2026-09-12)

`swayosd-server` + `swayosd-libinput-backend` are gone. `shared/osd/OsdWindow.qml`
is a single bottom-centre pill — on the focused output unless the caller names
one — with a glyph, level track and percentage for volume/backlight, or a glyph
and a word for a lock key or a message (below). It is held for
2500ms, up from swayosd's 1000ms: the pill spends part of that rising and
dropping, and a second left it leaving about as soon as it was read. The
dotfiles side changed with it: the volume
binds no longer call `swayosd-client`, the brightness binds no longer call
`brightnessctl`, and three new non-consuming lock-key binds were added.

`AudioService.maxPct` (100) is the ceiling `swayosd-client` ran the volume
binds at by default, and what the bar's wheel had always clamped to; the OSD's
track is scaled to it. A volume already past it (set in pavucontrol) becomes
the ceiling for that bump instead: clamping every write to 100 made one step
*up* from 130% land on 100 (2026-09-28 review).

**It is painted as a notification surface, not as a bar pill.** Its geometry
(`pillWidth`, `pillHeight`, `overshoot`, `bump`, …) is its own, declared at the
top of `OsdWindow.qml`; every colour comes from `NotificationTheme.qml` — `bgFloating` plate, `borderSubtle` edge,
`text`/`textDisabled` labels, `bgSelected` fill. The plate takes `bgFloating`
whole, alpha included: it floats over the desktop the way a toast does, so it
is the same material and reads as one. (It used to hold its own alpha in
`Theme.osdOpacity` on the grounds that the OSD lands over whatever is on
screen where a toast is read at leisure — 0.89 against 0.875, a difference
nobody could see. Removed 2026-09-14 when the toasts were made to match it,
and the shared value then went to 0.94 for both; see notes/notifications.md.) That plate carries real alpha, so `quickshell-osd` needs the same
`blur` layerrule the control centre has, plus `no_anim` — the window springs
itself in and out, and Hyprland fading it too double-animates.

**It rises out of the bottom edge and drops back under it.** That needs a
surface reaching the edge, so `margins.bottom` is 0 and the resting gap is room
*inside* the surface: one `travel` property is both the surface height and the
slide distance (the gap plus `pillHeight`), and the pill's `y` is a pixel spring
between `travel` and 0. Animating the layer-shell margin instead would
reconfigure the surface every frame. The earlier fade-and-scale is gone —
nothing here uses opacity except the reveal below — and the surface is far
larger than the pill it paints, which the `blur` layerrule does not mind:
Hyprland masks the blur by the surface's alpha, the same way the full-screen
control-centre surface gets blur only under its plate.

### Entry and exit are staged, off spring values rather than timers (2026-09-14)

What rises out of the edge is only the icon — a stadium `2 * pillPadding +
glyph.width` wide, so the glyph sits dead centre of it whatever the icon's
advance turns out to be — and the plate springs open horizontally around it as
it lands. Going away, the plate narrows back to the glyph, the pill hops a few
pixels *up* as a wind-up, and then drops under the edge. Measured on DP-1 with
a `grim` burst (~17ms/frame, converted back to logical px):

| stage | entry | exit |
|---|---|---|
| plate widens / narrows | 247 → 500ms (peaks 431px) | 2542 → 2810ms |
| glyph pill rises / drops | 0 → 245ms | 2843 → 3005ms |
| bump past the resting line | ~10px, apex ~310ms | ~18px, from 2710ms, apex 2843ms |
| settles | 420px wide by ~690ms | off the edge at 3005ms |

**Nothing here waits on a timer.** Three latches, each set the moment a spring
*value* reaches a place:

| latch | set when | releases |
|---|---|---|
| `risen` | `slide.value <= 0`, i.e. the pill first reaches its resting line | the widening |
| `narrowed` | `opened <= 0.2`, i.e. the plate is a fifth from shut | the wind-up |
| `wound` | `slide.value <= -bump` | the drop |

**Where those two thresholds sit is the whole difference between the entry
reading as one gesture and the exit reading as three.** Reported as "the slide
down looks a bit weird but I can't explain why", and the cause was that the
exit's stages did not overlap where the entry's do. Measured: the widening
starts at 250ms with the rise's bump and ~270ms of its settling still to run,
so stage 2 happens *inside* stage 1. The exit released the wind-up at
`opened <= 0.06`, by which point the plate had done 95% of its narrowing and
the only thing still moving was a 0.4px-a-frame residual — invisible, so the
narrowing, the hop and the drop each read as a separate beat. At `0.2` the
width is still closing ~7px a frame when the pill starts to rise, and the
plate finishes shutting while it is in the air. Lengthening the overlap is
free: the exit got *shorter*, because the later stages start sooner.

They are latches and not plain comparisons because every one of these springs
crosses its trigger and comes back: the rise oscillates around the resting
line, so `risen` as a bare `slide.value <= 0` collapses the plate again on the
first dip below it and the two springs fight. `risen` and `wound` are cleared
in `onShowingChanged`; `wound` starts **true**, or a freshly loaded shell winds
the pill up into view instead of parking it under the edge.

Staging this way is also what makes an OSD re-shown mid-exit reverse from
wherever it got to rather than restart — verified by re-triggering at 2.62s,
where the plate turned round at 188px and grew straight back to full without
the pill ever dropping. A timer-driven sequence has to special-case that.

Four things the stages imply:

- **The surface carries `overshoot` of slack**, 32px, on both axes: either
  side of the widest pill for the expansion to overshoot into, and above the
  pill's resting place for the two bumps. A window clips its contents. It is
  transparent, so it neither blurs nor takes input, and `travel` still means
  the distance the pill covers rather than the surface's height — the resting
  `y` is the slack itself.
- **The rise is under damped, the drop is not** (`damping: showing ? 12.3 :
  18.2` over stiffness 136). ζ≈0.68 going up gives the ~10px bump the pill
  lands with; the drop must not undershoot, or the pill would sink past the
  bottom of the screen and bounce back into view.
- **The wind-up aims past `bump`** and stops where the `wound` latch
  catches it, so the two numbers split the gesture cleanly: `bump` is the
  hop's *height*, and the multiplier is its *speed*. A spring tuned for
  `travel` takes ~200ms to settle 18px, ~95ms to pass through them at 2.5x
  and ~150 at 1.5x, and the flip to `travel` decelerates it so hard that the
  apex lands within ~5% of the latch whichever is used. 2.5x shipped first and
  read as a flick; it is 1.5x. The hop is close to free either way — the pill
  leaves it with downward speed, so the drop that follows is quicker by about
  what the hop took.
- **The wind-up is nearly twice the rise's bump**, by request — 18px against
  ~10px. The rise's is the tail of a landing and the wind-up is a gesture in
  its own right, so matching them made the exit read as the weaker of the two.
- **The drop aims 1.5x past the edge** and the third branch of
  `onValueChanged` parks the spring the moment the pill clears it. Aimed at
  the edge exactly, a spring *decelerates* into it — the measured drop fell
  from 24px a frame to 10 and then crept the last pixels for a third of a
  second, which is an ease-out on an exit. Aimed past, the pill is still doing
  ~16px a frame when the last of it crosses, and the whole drop takes 160ms
  rather than 280. The parking is what keeps the next rise starting from the
  edge instead of from 1.5x below it, and it stops the spring's frames early.
- **The closing width spring is damped past 1** (`damping: risen ? 16.5 : 24`).
  Symmetric damping undershot the collapsed width by 11px on the way out,
  which narrows the plate past the glyph it is meant to be a plate for.

**Every show re-arms `slide`** (`onShowingChanged`, 2026-11-15). A show
landing while the plate is still closing, *and* moving to an output with
another `travel` (height or scale), was lost: no layer, then a ghost when the
hide timer fired. `OsdService.show` sets the screen before the kind, so
`onTravelChanged` parks the pill while `showing` is still false, and `snapTo`
drops the spring's target; in that stage `slide.to` was already 0, so
`onToChanged` never fired. Retargeting in `onTravelChanged` instead is wrong:
`travel` also changes with no show (an output unplugged mid-exit), and with
`to` at 0 the pill would rise for nothing. The sideways twin of the same
`snapTo` trap is under "Moving to a narrower output mid-show". Verified on
DP-1 → DP-2 at every exit stage, DP-2 → HDMI-A-1 and DP-2 → DP-1.

Everything past the glyph — the track and the percentage, or the lock word —
lives in one `detail` item whose opacity ramps over the second half of the
expansion (`opened` 0.45 → 0.80, `Ramp.reveal()`, which the hover popups
share) and which is `visible: opacity > 0`, so the
level layout never renders through the widths where its track has no room.
This is a plain opacity on unlayered text, not the layer/MultiEffect that
`notes/text.md` rules out.

**A word pill (lock key or message) hugs its word** rather than sitting
centred in a 420px plate: `openWidth` is `labelInset + lockLabel.width`, the
label capped at `maxLabelWidth` (see Script messages below for the cap). A
fixed-width plate would have to grow to a width the content does not fill,
and the glyph has to start at `pillPadding` from the left edge for the
collapsed shape to centre it.

**Timings were tuned in three passes, all by request**: both springs slowed
10% on the first cut, then the slide alone another 10%, then the bumps added.
The knob for the first two is `stiffness / 1.21` with `damping / 1.1`, which
stretches a spring's durations by 1.1 and leaves its damping ratio where it
was — scale the pair, never the stiffness alone, or the feel changes along
with the timing.

**Vertical position is a fraction of the output's height, not a fixed margin**,
so it lands in the same place on a 1440 and a 2160 panel. swayosd did the same:
`osd_window.rs:114` is `margin_bottom = mon_height * (1.0 - top_margin)` with
`top_margin` defaulting to `0.85`, i.e. 15% off the bottom. `bottomEdgeFraction`
is 0.07 — deliberately lower than swayosd sat, by request.

Three services back it. `AudioService` took the default-sink state, the icon
ternary, the `PwObjectTracker` and the write clamp out of `Volume.qml`, which is
now a thin view like `Backlight.qml` is over `BacklightService`; the OSD and the
bar module read the same `pct`/`muted`/`icon`. `BacklightService` gained
`icon` and `bumpPercent()` (perceptual points, the unit `brightnessctl -e s ±N%`
moved in, so the keys behave as they did). `OsdService` holds what is showing
(`kind`), where (`screen`), and a message's payload.

**Who calls it.** Every trigger but one goes through `Ipc.qml`: the `osd`
target's `volume`/`mute`/`brightness`/`lock` handlers, which the keybinds call,
its `message` handler, which scripts call, and the `bar` target, which shows a
message after an auto-hide override. The exception is a default audio device
change, which Quickshell sees in Pipewire itself, so `OsdService` connects to
`AudioService.defaultChanged` directly (below). `show(kind, screen?)` lands on
`Screens.focused()` when no screen is given — a keybind has no widget to
report one — and keeps the last screen otherwise, so a hide animation
finishes where it started.

**Messages.** `showMessage(glyph, text, on, screen?)` shows the `"message"`
kind: styled like a lock key, `on` lighting the glyph, the text in place of
the lock word. Callers are the bar's visibility OSD (`Ipc.qml`'s
`applyBarOverride`: "Bar hidden · this workspace · override", on the bar's own
output) and scripts, below.

**Everything is keybind-driven, deliberately.** The alternative is a daemon
holding evdev open, which is what both prior arts do: swayosd runs a
*root* libinput backend, and DankMaterialShell runs a Go helper that needs the
user in the `input` group (`dms setup` runs `usermod -a -G input`; it prints
"Caps Lock OSD will be unavailable" when that fails, and it only covers Caps
Lock, not Num/Scroll). This machine's user *is* in `input`, so an `evtest`
reader was possible — see Rejected. A keybind costs nothing until pressed.

### Script messages over IPC (2026-11-15)

`qs ipc call osd message <glyph> <text>`, for scripts that want feedback on
something they just did. It is for transient feedback only: anything that
should be kept or read later is a notification. A caller wanting a fallback
can test `qs`'s exit status: non-zero means no shell is answering — `qs`
exits 0 for a call the running shell has no handler for, so that case shows
nothing.

The audio switchers (`~/.local/bin/switch-audio`,
`~/.config/hypr/scripts/wofi-audio`) called it until 2026-11-16, when the OSD
started announcing default device changes itself (below). They give no
success feedback now, so picking the device that is already the default, or
`switch-audio sdac` capping the volume to 60%, shows nothing — by request.

Two strings and nothing else, always lit (see Rejected). The glyph is a
literal Nerd Font character (bash: `$'\U000f02cb'`). Whitespace is
flattened in the handler: a real newline wraps even in a PlainText label,
giving two lines in a one-line pill, and blank text or glyph would draw an
empty plate. An empty glyph falls back to `󰋽` in `OsdWindow`'s glyph switch,
beside every other kind's glyph.

**Empty text is an icon-only pill** (`iconOnly`): `openWidth` is
`collapsedWidth`, so the glyph rises, holds and drops without the plate ever
widening. Left to the general formula it would open to `3 * pillPadding +
glyph`, a padding of empty plate right of the glyph. The exit needs a special
case: `Ramp.ramp` over an empty span is 1 whenever the width is at its
target, so `opened` never falls to the `narrowed` threshold and the pill
would never drop. `narrowed` is therefore true outright for an icon-only
pill. Measured with a `grim` burst: risen with its bump by ~250ms, wind-up at
~2.64s, off the edge by ~2.88s, the same exit as a word pill. Idle cost
returns to baseline (~11 wakeups/s) after it.

**A word pill grows to a quarter of the output's logical width**
(`maxWidthFraction`, never under `pillWidth`), then elides; level pills keep
the fixed 420px (see Rejected). The logical pixel is already about one
physical size on every output here (from EDID: DP-1, 4K at 1.25 and 70cm
wide, is ~111 logical px per inch; the 1440 panels, 60cm wide, ~108), so
what a larger screen has is width, and a share of width is what follows it:
640px on 2560-wide outputs, 768 on DP-1.

The surface is sized to that cap plus `overshoot`, because a window clips its
contents: without it the bar's longest message ("… · forced, output override
wins", ~400px of text) opens wider than the surface and loses its plate's
ends. The wider surface takes no input (`mask` is empty) and gets blur only
under the plate (Hyprland masks blur by alpha), but it is not free while
animating: Hyprland redraws and blurs the whole surface each frame, ~800px
wide on DP-1 and 672 on the 1440 panels against 452 at a level pill's width, so 1.5–1.8x the
area while the OSD is up. Idle cost is unchanged — the surface unmaps.

**Moving to a narrower output mid-show.** The cap follows the output, so the
surface shrinks at once while the plate is still at the old screen's width
(mid-show, or closing mid-exit). `onMaxPillWidthChanged` cuts `expand` to the
new cap and retargets it, the sideways twin of `onTravelChanged`'s re-park;
the retarget is needed because `snapTo` also overwrites the spring's target,
and if `to` then never changes the plate would stay at the cut width. The
pill is centred off `osd.implicitWidth`, not `parent.width`, for the same
move: Hyprland places the surface by the requested size at once, while
`parent.width` follows a configure later. Measured on a DP-1 → DP-2 move
mid-show, centring off `parent.width` put the pill (800 − 672) / 2 = 64px
right of centre for the first three or four frames, then it jumped. `y` was
already off `implicitHeight`.

Accepted as is (2026-11-15): the reverse move, to a *wider* output, cuts up
to 48px off the plate's right end for ~2 frames, on long messages only. The
old, narrower buffer is still on screen while Hyprland already places the
surface by the new size; centring off `parent.width` instead trades that for
the pill sitting 64px off centre. The clean fix is one surface width for
every output (the widest cap of any connected one), which also retires
`onMaxPillWidthChanged`, at the cost of a wider blur box on the smaller
panels. And the cut zeroes the closing plate's velocity, but that is never
seen here: every output pair that differs in width also differs in height,
so `onTravelChanged` has already parked the pill under the edge.

### Default audio device changes (2026-11-16)

When Pipewire's default sink or source moves to another device — `wpctl
set-default`, pavucontrol, a script, or WirePlumber falling back after an
unplug — `AudioService` emits `defaultChanged(glyph, text)` and `OsdService`
shows it as a lit message. One glyph per direction, `󰓃` sink and `󰍬` source,
and the node's `nickname` (`SDAC`, `EDIFIER S3000 Pro`, `27GL850`), falling back
to `description` then `name`. Both moving gives both glyphs, and
`"EDIFIER S3000 Pro — RODE Podcaster v2"` — an em dash between em spaces
(U+2003), because `·` already means "a detail follows" in this pill — or the
name once when they share it, as one headset's sink and source do
(`Avantree DG60P`).

**Compared by `node.name`, not the object**: a PipeWire or WirePlumber restart
recreates the nodes under the same names, and the default metadata itself
names nodes by `node.name`. A null default is skipped — it is the gap between
an unplug ("Default sink destroyed", then WirePlumber's pick) or a restart.

**What stays silent:**

| case | why |
|---|---|
| shell start, `qs` reload | first sighting per direction is a baseline; `Component.onCompleted` takes it on reload, where `Pipewire.ready` is already true and nothing changes |
| first 2s after Pipewire (re)connects | `grace`: WirePlumber can publish the default late, or pick a fallback before a USB DAC enumerates — either would otherwise announce at login |
| changes while `Pipewire.ready` is false | same reason |
| a transient fallback after a null default | `settle` waits 1s after a gap, below |
| new name, same label | the same device recreated |
| last device removed, default null | nothing to name |

**One pill per plug event**: the sink and the source of one card move a few ms
apart, and `settle` (100ms) gathers them. Enough for one USB card, where ACP
creates both nodes together.

**After a null default it waits 1s instead** (`sawGap`). A WirePlumber-only
restart (`systemctl --user restart wireplumber`) leaves Quickshell's
connection up, so `Pipewire.ready` never drops and `grace` never starts — yet
every ALSA node is WirePlumber's and is destroyed, and while it re-enumerates
six cards it may publish a fallback (SDAC) before the configured EDIFIER
exists. At 100ms that is two pills, SDAC then EDIFIER; at 1s the fallback is
usually superseded and the final pick equals the old name, so nothing shows.
Inferred from the review (2026-11-16), not exercised. The cost is an unplug's
fallback pill arriving a second late; a deliberate switch never passes
through null, so it stays at 100ms. This also covers a Bluetooth profile
switch, should a `bluez_` node ever appear.

`settle` reads `Pipewire.ready` and `grace` when it fires, not when armed:
otherwise a change pending across a disconnect was announced inside `grace`
after a sub-100ms reconnect.

**No tracking needed for any of it**: `name`, `nickname` and `description` are
constant properties, filled from the registry global before a node is bound
(checked in the qmltypes and `pw-cli ls Node`). Only `properties` needs a
binding, and nothing here reads it — so there is no waiting for the new
default to be `ready` either.

`OsdService` holds the connection rather than `Ipc.qml`, because no IPC call
is behind it: a lock key is seen by Hyprland and passed in over IPC, this is
seen by Quickshell. `OsdService` is built at start-up (shell.qml reads
`OsdService.screen`), which in turn builds `AudioService` then, not on first
use — otherwise the baseline would be taken by whatever first touched it.

Verified on DP-1: SDAC ↔ EDIFIER each show one pill; sink and source to the
Avantree together show both glyphs and the name once; back to EDIFIER/RODE
shows `EDIFIER S3000 Pro — RODE Podcaster v2`; a `qs` reload shows nothing.
Not exercised: the restart and login paths through `grace` and the 1s
`settle`.

### Three Quickshell behaviours this ran into, all measured

**LED class attributes raise no inotify event.** An inotify watch on all ten
`/sys/class/leds/*{caps,num}lock/brightness` nodes, with `IN_ALL_EVENTS`, saw
**zero** events across a run in which the keys were demonstrably pressed
(swayosd's layer opened three times in Hyprland's event socket over the same
window). The kernel never `sysfs_notify()`s them. So unlike
`/sys/class/backlight` — which does, and which `BacklightService` therefore
watches — there is nothing to subscribe to here, and the state can only be
read on demand.

**`FileView` loads synchronously exactly once.** `blockLoading: true` blocks
the *initial* load and nothing after it. Both obvious shapes silently return
stale text:

| shape | result |
|---|---|
| one FileView, `path` re-pointed per node, then `reload()` + `text()` | every read returns the **first** file's content |
| one FileView on a fixed path, file changed underneath, `reload()` + `text()` | returns the **pre-change** content |

Proven with two files holding `0` and `1`: alternating between them returned
`"0\n"` four times. This is why `BacklightService` reads through `onLoaded`
rather than inline — the pattern was already right there, and it is the only
one that works. `LockKeysService` therefore shells out to
`cat /sys/class/leds/*::<key>/brightness`: async, so the OSD is shown from the
`refreshed(key)` signal rather than beside the `refresh()` call, and the glob
makes hotplug and multi-keyboard setups free. A fork per lock keypress is not
the polling `sh -c cat` this repo removed from BacklightService;
swayosd-client was a whole process spawn per keypress too.

**A QML singleton is built on first use, and the first use here is a
keypress.** The first `LockKeysService` design enumerated the LED nodes with a
`FolderListModel`, which takes ~500ms to reach `Ready`. Since nothing touched
the singleton until the IPC call, it was *created* by that call, its listing
was empty, and every lock read came back `false` — a Num Lock that was
demonstrably on reported "off". Any singleton whose state depends on an async
load, and which is only ever reached from a one-shot event, has this bug. The
`cat` design has no such state and sidesteps it.

### A fixed grey on a translucent plate loses its contrast over a bright window

Reported as the volume track being nearly invisible with the OSD over a white
window. The plate carries real alpha and is blurred, so what it *renders* as
follows whatever is behind it, while `bgButton` (`#404040`) is absolute. Same
pixels, two backdrops:

| backdrop | plate | track | Δ |
|---|---|---|---|
| dark desktop `(45,53,59)` | 43 | 64 | **+20** |
| white window `(255,255,255)` | 69 | 64 | **−5** |

The plate travels 43 → 69 and crosses the fixed track on the way. Predictable
from the numbers: over backdrop *B* the plate resolves to `0.144 + 0.125·B`,
which is 0.167 (43) over that desktop and 0.269 (69) over white — both match
the measurement.

**Fixed by specifying the track as a tint over the plate instead of a colour**
— `NotificationTheme.bgOverlay`, white at 10%. Its delta is then `0.10·(1 − plate)`,
which barely moves across the range, and 0.10 was picked so the dark case keeps
the appearance `bgButton` already had. Measured after: **+21** over the desktop
(64 → 65, i.e. unchanged), **+19** over white (64 → 88). The teal fill needed
nothing — it is opaque and reads on both.


The plate's alpha was later raised on its own account, 0.875 → 0.94, which
narrows its travel from 43..69 to **43..55** and so damps this effect at the
source. It is not a substitute for `bgOverlay` — a fixed grey still drifts
against the plate across that range — but the two compound: Δ is now +22 over
the desktop and +20 over white.

**`bgButton` still has this latent** at its one remaining call site,
`NotificationCard.qml`'s action chips — cards are translucent too. Left alone
because nobody has reported it; `bgOverlay` is the fix if they do.

### No drop shadow on the pill, tried and reverted (2026-09-19)

Tried when `shared/DropShadow.qml` was factored out of the toasts and the
control centre: the plate `Rectangle` as the effect's source, hidden so the
effect painted it once (the toasts' double-composite trap, notes/notifications.md).
Compared at 1.25 scale over the dark desktop, with and without: a few levels
darker along the bottom edge and nothing else — the 1px `borderSubtle` outline
and the blur are what define the pill's edge. Removed by request; the toasts
kept theirs. The pill comment's "never `layer`" rule stands in full again.

### xkb unlocks a lock key on *release*, so the read has to wait it out

Reported as "it always shows Caps Lock on". Measured against Hyprland's event
socket, with a 0.5ms poll on the LED nodes:

| press | LED flips | OSD opens | |
|---|---|---|---|
| turning caps **on** | 4.459s | 4.474s | LED 15ms **before** — read is correct |
| turning caps **off** | 6.914s | 6.800s | LED 114ms **after** — read is stale |

xkb *locks* on key press but *unlocks* on key release, so the second press of
a pair doesn't reach the LED until the key comes back up. The 114ms is just
how long the key was held; there is no fixed delay to compensate with. A bind
reaches this process ~12ms after the key (`hyprctl dispatch exec` → process
running is ~4ms, `qs ipc call` round trip ~8ms), so a press-bound read lands
squarely inside that window.

Binding on release instead doesn't work (see Rejected), so the read has to
cope with landing early.

The fix needs no timing guess: **a lock key always toggles**, so a read that
comes back equal to the value from before the press is provably early.
`LockKeysService` re-reads every 30ms until the value changes, giving up after
1000ms (which is also what keeps a keyboard with no LED node from waiting
forever). Verified: after the change, the LED flip precedes the OSD open on
every press in both directions — 16.413→16.449, 43.050→43.074, 46.202→46.239.

That comparison needs a trustworthy "before", which is why the service primes
all three locks with silent reads in `Component.onCompleted` — otherwise the
first press of a session has nothing to be early against. The priming is
observable: an IPC call that toggles nothing takes the full 1000ms budget to
show, where an unprimed key shows immediately. A lock key pressed in the ~50ms
before priming lands still takes its first read as final.

## Rejected

- **Glyphs by device** (headphones for a `headset` form factor, a TV for
  `hdmi`, Bluetooth for `bluez_`, or a per-device table): `device.icon-name`
  is `audio-card-analog` on every node and only one sets a form factor, so it
  would be guesswork or a table to maintain. One glyph per direction, by request.
- **A separate `AudioDeviceService`**: it would duplicate the default-sink
  binding `AudioService` already owns.
- **Keeping the audio scripts' `osd message` calls** next to the watch: the
  OSD would show twice, the script's text replacing the watch's a frame later.
- **Script messages only when the watch can't see it** (the device already
  default, the SDAC volume cap): not wanted.
- **Starting `grace` when both defaults go null together**, for the
  WirePlumber restart: the 1s `settle` after any gap covers it and an unplug
  of one direction too.
- **Icon names in the message IPC** instead of literal glyphs: there is no
  name→glyph table in this repo to look one up in, and a script can spell
  any glyph as `$'\U000fXXXX'`.
- **An `on` argument on the message IPC**: `qs ipc` has no optional
  arguments, and a script reporting something it just did wants the lit
  glyph.
- **A wider level pill on large outputs**: its track would only get longer;
  the extra room is for words.
- **An evdev reader** (`evtest`, as swayosd's root libinput backend and DMS's
  Go helper do): one long-lived subprocess per keyboard plus hotplug handling,
  waking on every event, against the "no owned subprocesses" rule and the
  idle-CPU budget.
- **Binding the lock keys on release** (`release = true`): LED transitions
  with *no* `openlayer>>quickshell-osd` event at all — Hyprland never fires
  them.
- **An opaque plate** to fix the track's contrast over bright windows: the
  blur is the look.
- **An outline on the track**: treats the symptom, and an absolute outline
  colour has the same problem as the absolute track did.
- **A drop shadow on the pill** (2026-09-19): a few levels darker along the
  bottom edge and nothing else; the outline and blur already define the edge.
- **Its own `Theme.osdOpacity`**: 0.89 against the toasts' 0.875, a
  difference nobody could see; both share `bgFloating` now.

