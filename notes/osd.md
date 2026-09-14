# OSD

## Native OSD, replacing swayosd (2026-09-12)

`swayosd-server` + `swayosd-libinput-backend` are gone. `shared/osd/OsdWindow.qml`
is a single bottom-centre pill on the focused output — glyph, level track,
percentage for volume/backlight; glyph and a word for a lock key — held for
2500ms, up from swayosd's 1000ms: the pill spends part of that rising and
dropping, and a second left it leaving about as soon as it was read. The
dotfiles side changed with it: the volume
binds no longer call `swayosd-client`, the brightness binds no longer call
`brightnessctl`, and three new non-consuming lock-key binds were added.

**It is painted as a notification surface, not as a bar pill.** Metrics live in
`Theme.qml` with the rest of the shell's, but every colour comes from
`NotificationTheme.qml` — `bgFloating` plate, `borderSubtle` edge,
`text`/`textDisabled` labels, `bgSelected` fill. The plate takes that hue at
its own alpha (`Theme.osdOpacity`, 0.94) rather than `bgFloating`'s 0.875: a
toast is read at leisure, the OSD lands over whatever is on screen, and raising
`bgFloating` would move the toasts with it. It floats over the desktop the
way a toast does, so it belongs to that palette; the split is called out at
both ends. That plate carries real alpha, so `quickshell-osd` needs the same
`blur` layerrule the control centre has, plus `no_anim` — the window springs
itself in and out, and Hyprland fading it too double-animates.

**It rises out of the bottom edge and drops back under it.** That needs a
surface reaching the edge, so `margins.bottom` is 0 and the resting gap is room
*inside* the surface: one `travel` property is both the surface height and the
slide distance (the gap plus `osdHeight`), and the pill's `y` is a pixel spring
between `travel` and 0. Animating the layer-shell margin instead would
reconfigure the surface every frame. The earlier fade-and-scale is gone —
nothing here uses opacity except the reveal below — and the surface is far
larger than the pill it paints, which the `blur` layerrule does not mind:
Hyprland masks the blur by the surface's alpha, the same way the full-screen
control-centre surface gets blur only under its plate.

### Entry and exit are staged, off spring values rather than timers (2026-09-14)

What rises out of the edge is only the icon — a stadium `2 * osdPadding +
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
| `wound` | `slide.value <= -osdBump` | the drop |

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

- **The surface carries `osdOvershoot` of slack**, 32px, on both axes: either
  side of the widest pill for the expansion to overshoot into, and above the
  pill's resting place for the two bumps. A window clips its contents. It is
  transparent, so it neither blurs nor takes input, and `travel` still means
  the distance the pill covers rather than the surface's height — the resting
  `y` is the slack itself.
- **The rise is under damped, the drop is not** (`damping: showing ? 12.3 :
  18.2` over stiffness 136). ζ≈0.68 going up gives the ~10px bump the pill
  lands with; the drop must not undershoot, or the pill would sink past the
  bottom of the screen and bounce back into view.
- **The wind-up aims past `osdBump`** and stops where the `wound` latch
  catches it, so the two numbers split the gesture cleanly: `osdBump` is the
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

Everything past the glyph — the track and the percentage, or the lock word —
lives in one `detail` item whose opacity ramps over the second half of the
expansion (`opened` 0.45 → 0.80) and which is `visible: opacity > 0`, so the
level layout never renders through the widths where its track has no room.
This is a plain opacity on unlayered text, not the layer/MultiEffect that
`notes/text.md` rules out.

**A lock-key pill hugs its word** rather than sitting centred in a 420px
plate: `openWidth` is `3 * osdPadding + glyph.width + lockLabel.implicitWidth`
for those kinds. A fixed-width plate would have to grow to a width the content
does not fill, and the glyph has to start at `osdPadding` from the left edge
for the collapsed shape to centre it.

**Timings were tuned in three passes, all by request**: both springs slowed
10% on the first cut, then the slide alone another 10%, then the bumps added.
The knob for the first two is `stiffness / 1.21` with `damping / 1.1`, which
stretches a spring's durations by 1.1 and leaves its damping ratio where it
was — scale the pair, never the stiffness alone, or the feel changes along
with the timing.

**Vertical position is a fraction of the output's height, not a fixed margin**,
so it lands in the same place on a 1440 and a 2160 panel. swayosd did the same:
`osd_window.rs:114` is `margin_bottom = mon_height * (1.0 - top_margin)` with
`top_margin` defaulting to `0.85`, i.e. 15% off the bottom. `Theme.osdBottomEdgeFraction`
is 0.07 — deliberately lower than swayosd sat, by request.

Three services back it. `AudioService` took the default-sink state, the icon
ternary, the `PwObjectTracker` and the write clamp out of `Volume.qml`, which is
now a thin view like `Backlight.qml` is over `BacklightService`; the OSD and the
bar module read the same `pct`/`muted`/`icon`. `BacklightService` gained
`icon` and `bumpPercent()` (perceptual points, the unit `brightnessctl -e s ±N%`
moved in, so the keys behave as they did). `OsdService` holds only what is
showing and where.

**Everything is keybind-driven, deliberately.** The alternative is a daemon
holding evdev open, which is what both prior arts do: swayosd runs a
*root* libinput backend, and DankMaterialShell runs a Go helper that needs the
user in the `input` group (`dms setup` runs `usermod -a -G input`; it prints
"Caps Lock OSD will be unavailable" when that fails, and it only covers Caps
Lock, not Num/Scroll). This machine's user *is* in `input`, so an `evtest`
reader was possible — and rejected: it is one long-lived subprocess per
keyboard plus hotplug handling, waking on every event, against this repo's
"no owned subprocesses" rule and its idle-CPU budget. A keybind costs nothing
until pressed.

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

Rejected: making the plate opaque (that is the blur, and the blur is the look),
and an outline on the track (treats the symptom, and an absolute outline colour
has the identical problem).

The plate's alpha was later raised on its own account, 0.875 → 0.94, which
narrows its travel from 43..69 to **43..55** and so damps this effect at the
source. It is not a substitute for `bgOverlay` — a fixed grey still drifts
against the plate across that range — but the two compound: Δ is now +22 over
the desktop and +20 over white.

**`bgButton` still has this latent** at its one remaining call site,
`NotificationCard.qml`'s action chips — cards are translucent too. Left alone
because nobody has reported it; `bgOverlay` is the fix if they do.

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

**Binding on release instead does not work**: `release = true` on all three
lock binds produced LED transitions with *no* `openlayer>>quickshell-osd`
event at all — Hyprland never fires them. Reverted to press.

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

### Two smaller traps in shell.qml

`ShellRoot` takes **no attached objects**: `Component.onCompleted` on it is not
a lint error but a load-time one — `Non-existent attached object` — which takes
the whole config down. And `Connections` resolves under `import QtQuick`, not
`import QtQml`; qmllint accepts the latter, the runtime rejects it with
`Connections is not a type`. Both failures leave the running shell on its last
good config, so a change that "did nothing" is worth checking against
`qs log -i <id>` before it is worth debugging.

