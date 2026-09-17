# Text rendering

## Text weight goes through Inter's `wght` axis, not `font.bold` (2026-09-12)

Started from a question about `FREETYPE_PROPERTIES='cff:no-stem-darkening=0
autofitter:no-stem-darkening=0'`, carried over from the waybar config, where
it is set in `~/.config/sway_gaming/scripts/start.sh`. Two findings before any
change: it never reached this shell (`qs` runs from systemd, PPID 1, and
`/proc/<pid>/environ` has no `FREETYPE_PROPERTIES`), and half of it could not
have done anything if it had — the `cff:` driver only touches PostScript
outlines, while every font here is TrueType `glyf` (InterVariable.ttf,
SymbolsNerdFont-Regular.ttf, Hack-Regular.ttf).

The `autofitter:` half *would* apply: InterVariable has no `fpgm`/`prep`/`cvt`,
so with `/etc/fonts/conf.d/10-hinting-slight.conf` the autohinter runs on every
glyph. Not taken, because FreeType's own docs say stem darkening only
compensates correctly "when using linear alpha blending and gamma correction …
When not using [them], glyphs will appear heavy and fuzzy!" Qt blends text in
sRGB. It is a rasterizer-level fake embolden, and process-wide.

**What was done instead.** Inter is variable — axes `opsz` 14..32 (pinned at
14 in every named instance, and `Theme.fontSize` 12 is already below the
minimum) and `wght` 100..900. `StyledText` now sets
`font.variableAxes: ({ "wght": wght })`, `wght` defaulting to `Theme.fontWeight`
(450) and `bold` mapping to `Theme.fontWeightBold` (700).

Measured at pixelSize 12, ink = summed coverage over a grabbed render of the
same string, advance = grab width:

| | advance | ink |
|---|---|---|
| plain (wght 400) | 126px | 320 |
| `font.weight: 450` | 126px | 320 |
| `font.weight: 500` | 126px | 320 |
| axis `wght: 450` | 127px | 351 |
| `font.bold: true` | 126px | 472 |
| `font.styleName: "Bold"` | 130px | 486 |
| axis `wght: 700` | 130px | 479 |
| `font.styleName: "ExtraBold"` | 132px | 544.5 |
| axis `wght: 800` | 132px | 544.8 |

So: by-number weight requests snap to a named instance and 450/500 both come
back as Regular; `font.bold` keeps Regular's advances while adding ink, i.e.
Qt synthesises it rather than loading the Bold instance the `styleName` row
reaches; and the axis reproduces the named instances exactly (800 vs
ExtraBold: 132px/544.8 against 132px/544.5).

**Two traps this creates**, both silent, which is why the style note is a rule
and not a preference:

- An axis set on `StyledText` overrides a site's `font.bold` *and*
  `font.styleName`. `font.bold: true` over the 450 axis re-synthesises bold
  from the 450 outline (127px, ink 504 — heavier and smeared than either real
  face), and `font.styleName: "ExtraBold"` over it renders at 450 (ink 345).
  `NotificationCard`'s action label used that styleName and is now `wght: 800`.
- Binding the axis to `font.weight` (`({ "wght": font.weight })`, so sites
  could keep using `font.bold`) resolves to the right values but logs a
  binding loop at every text site — writing `variableAxes` notifies the whole
  `font` group, which re-evaluates the binding. Hence the separate
  `bold`/`wght` properties, which don't read back into `font`.

`Workspaces.qml`'s `FontMetrics` carries the same axis, or pill widths would be
sized off a slightly narrower face than the labels draw with (`advanceWidth`
does honour `variableAxes`: "browser" is 46.27px at 400, 46.61px at 450,
48.30px at 700).

## Text is unhinted unless an item says so (2026-09-12)

Follow-up to the weight work above: text still read blurry on the two 1440p
screens (HDMI-A-1 and DP-2, both scale 1, 109ppi) while the 4K at 1.25 looked
fine. Three candidate causes, measured rather than guessed.

**1. Hinting — this was the real one.** `fc-match -v "Inter Variable"` reports
`hintstyle: 1` (hintslight) and `hinting: True`, but Qt Quick's native text
path ignores it: an item with no `font.hintingPreference` renders identically
to one asking for `Font.PreferNoHinting` — same ink, same lit-pixel count, to
the decimal. The system-wide setting that shapes waybar and GTK never applied
to this bar at all.

A/B'd on the live bar by editing `StyledText`, letting it hot-reload and
grabbing the same clock label each time (`grim -g "2300,0 260x28"`), scored as
the share of the label's ink landing in fully covered pixels:

| | solid share |
|---|---|
| no preference (= `PreferNoHinting`) | 53.5% |
| `PreferVerticalHinting` | 55.6% |
| `PreferFullHinting` | 61.5% |
| `PreferFullHinting`, `Icon` opted out | 62.5% |

(Same window, so the rows are comparable; absolute values shift with the label
under the crop.)

**Full hinting was then reverted.** The numbers say it wins and the pixels say
it doesn't: at 12px the autohinter's full mode visibly mangles Inter, which is
drawn for unhinted rendering. Reported as "more artifacts than before" within
minutes of it going live, and confirmed at 9x on the same label — advances
round to whole pixels so letter spacing goes uneven, `p` grows a hard 1px
descender spur, `S` and `5` go blocky, and Nerd Font glyphs lose thin strokes
outright (the notification bell loses both motion arcs, which is what the
`Icon.qml` opt-out existed to work around).

Settled on `PreferVerticalHinting`: +2 points of solid share, every glyph still
the shape it was drawn as, no opt-out needed anywhere — `Icon`'s glyphs render
fine under it, bell arcs intact — and it matches what fontconfig already asks
for system-wide. The lesson worth keeping: a sharpness metric ranks full
hinting first, and looking at it at 9x settles the question the other way.
Measure to find the lever, look at the pixels to decide.

**2. Fractional item positions — not a factor.** Qt rounds a text item's
position to whole device pixels before rasterising: the same label at `x: 0`
and `x: 0.37` grabs byte-identical, and `x: 0.5` shifts a whole pixel rather
than blending across two. `Workspaces.qml`'s label `x`/`y` (unrounded, unlike
the selection pill's `Math.round`) therefore costs at most a pixel of
centring, never sharpness. Left alone.

> Confirmed and bounded on 2026-09-12: it also holds when the *ancestor* is
> off-grid, which is the case that actually comes up — a container half a
> device pixel out renders its text as sharply as one on the grid. The single
> exception is an item inside a layer (a `MultiEffect` source), whose texture
> is filtered rather than re-rasterised. See the section at the end.

**3. Subpixel antialiasing — rejected, and not reachable anyway.** The bar
renders pure greyscale AA today: across the glyph edges of a bar label the
per-channel alpha spread is 0.017 median, 0.02 max, i.e. every edge pixel is a
flat blend of foreground and background. fontconfig has no `rgba` set, and
there is no per-item Qt equivalent to turn on. Setting it globally would be
wrong here regardless: HDMI-A-1 runs `transform=3` (subpixels vertical, not
horizontal) and DP-1 is a QD-OLED with a non-stripe layout, so two screens of
three would fringe, and Qt has no per-screen control.

**What DankMaterialShell does** (asked during this work): nothing — no
`hintingPreference`, no `variableAxes` anywhere in the tree, and its
`DankCommon.StyledText` defaults `renderType` to `Text.QtRendering`
(distance-field), where hinting has no meaning at all. It exposes render type
(Qt/Native/Curve) and `renderTypeQuality` as user settings and takes weight
through plain `font.weight`, which on Inter Variable snaps to the named
instances as measured above. Nothing to borrow here.


## The control center was blurry on DP-1 because its content lived in a layer (2026-09-12)

Reported as "the notification panel is at the wrong resolution on DP-1 — it
looks like it takes DP-2's resolution". It does not. The surface is on the
right output, at the right size, rendered at DP-1's native resolution:

| suspected | measured |
|---|---|
| wrong output / stale `screen` | layer surface reports `DP-1 3072x1728`, correct for 3840÷1.25; reassigning `screen` mid-session keeps it |
| content scaled for another screen | panel title ink 154x20 px on DP-1 against 123x16 on DP-2 — exactly 1.25x |
| surface rendered small and upscaled | `WAYLAND_DEBUG=1`: `wp_fractional_scale_v1.preferred_scale(150)` (=1.25) and `create_immed(… 3840, 2160 …)`, i.e. buffers at native resolution, `wp_viewport.set_destination(3072, 1728)`. Quickshell is using fractional scaling; only `devicePixelRatio` looks integer, see below |
| the vulkan RHI backend | same render under the GL default |
| a degraded long-running instance | a freshly launched copy renders the panel pixel-identical to the live one (`compare -metric AE` = 0) |

**The cause: layer textures are filtered, glyphs are not.** Qt rounds a text
item's position to whole device pixels, so unlayered text is sharp wherever it
sits. A `MultiEffect` source item is different — it is rendered into a texture
and that texture is drawn with linear filtering, so a fractional destination
resamples everything inside it. Three identical labels on DP-1, the offset put
on their *container*, scored by how much of the glyph ink lands in fully
covered pixels:

| container offset | plain container | `MultiEffect` source |
|---|---|---|
| on-grid | 1645 full / 1229 midtone | 1728 full / 1101 midtone |
| ½ device pixel off | 1689 / 1179 | **1124 / 1757** |

Only the layered row collapses. `NotificationCenterPanel.qml` used
`source: panel` with the entire panel as the source, purely to get a drop
shadow, so all of its text was inside that texture — and the panel's resting
overscan (`rightMargin: -2`, with `NotificationCenterPanel.qml`'s `marginV: 50`) put its left
edge at device x 3217.5. `NotificationCard.qml` had always layered just a
background `Rectangle`, which is why the cards never showed this.

**Fix 1, the one that matters: the content moved out of the source.** `panel`
is now an empty background plate; the `MouseArea` and `ColumnLayout` are a
sibling `Item` drawn after the `MultiEffect`. Panel title, same crop:

| | full (≥230) | midtone (90..200) |
|---|---|---|
| layered, off-grid (the bug) | 261 | 869 |
| layered, snapped to the grid | 598 | 404 |
| unlayered, still off-grid | 610 | 394 |

Unlayered and *unsnapped* already beats layered-and-snapped, and needs to know
nothing about the output's scale — so it holds at 1.333 or 1.6 just as well.

**Fix 2, polish: `Screens.snap()` for the borders.** Geometry is still
antialiased honestly, so with the content out of the layer the panel's own 1px
border was still split when off-grid. One scanline across it:

```
off-grid (edge 3217.5):  47  61  54  41   ← two half-lit columns
snapped  (edge 3217.0):  46  74  41  41   ← one, full intensity
```

and the card outline inside the list, via `listPadding`:

```
off-grid (edge 3272.5):  36  92 142 143  95  48
snapped  (edge 3270.0):  37 143 143 143  48  48
```

`Screens.snap(length, screen)` rounds a logical length so `length * scale` is
whole. It cannot use `ShellScreen.devicePixelRatio`: that is the integer
`wl_output` scale Hyprland advertises for legacy clients — **2** on this 1.25
output — while the surface is rendered through `wp_fractional_scale_v1` at
1.25. Qt exposes the fractional value to QML nowhere, so `Screens.scaleFor()`
takes it from `Hyprland.monitorFor(screen).scale`. A rounder constant was tried
first and rejected: the multiple that stays on the grid is the denominator of
the scale (4 at 1.25, 3 at 1.333, 5 at 1.6), so no single constant covers the
outputs a config might meet.

Applied to the panel's margins, width and overscan, to `panelPadding` /
`listPadding` / `listCardMargin` at their call sites, and to the toast stack's
margins and `implicitWidth` (right-anchored, so the width places the left
edge). The theme keeps the designed numbers; only the call sites snap.

**Considered and not done.** Disabling the protocol
(`QT_WAYLAND_DISABLED_INTERFACES=wp_fractional_scale_manager_v1`) drops Qt back
to the integer output scale and recovers part of the sharpness on its own
(52.15 mean gradient against the off-grid 50.38), because the compositor then
downsamples a 2x render rather than filtering a misaligned texture. Rejected:
it makes Qt render every surface at 6144x3456 for a 3840-wide output, and it
treats the symptom. `QT_WAYLAND_DISABLE_FRACTIONAL_SCALE`, tried first, is not
a Qt variable at all — 6.11's `libQt6WaylandClient` has no such string.


## `snap()` is not enough in front of text: solve for the landing (2026-09-14)

Reported as "the text in notifications in the panel has some fringe/artifacts",
after the control centre's overscan changed (see `notes/panels.md`). In the
same screenshot the panel's *header* — "Notifications", "Do Not Disturb" — was
crisp and only the cards' text fringed, which is what located it: the two
subtrees differ by the list's own inset.

**Glyph origins are logical pixels; `snap()` only guarantees device pixels.**
Both facts were already in this file; together they leave a gap. The list's
26px inset snaps to 26.4 at scale 1.25 — a whole device pixel, so the card's
outline is exactly as crisp as intended — and 26.4 lands the card, and every
glyph in it, on a fractional *logical* x. The rasteriser then positions each
stem at its own subpixel offset and the weights alternate word to word. It
looks like a font-weight bug, not an alignment one. Vertical offsets in the
same chain are just as fractional (the panel rests at y = 50.4) and the text is
unaffected: baselines are rounded to whole device pixels, only horizontal
positioning is subpixel.

Measured, with the same notification on screen either side of the change:

| | card's absolute x | logical | device |
|---|---|---|---|
| before the overscan | 2573.6 + 16 + 26.4 | 2616.0 ✓ | 3270 ✓ |
| after it | 2572.0 + 16 + 26.4 | 2614.4 ✗ | 3268 ✓ |

So the old rendering was crisp *by luck*: the panel's own `-1.6` resting
overscan happened to cancel the inset's `+0.4`. Changing the overscan changed
the parity and the cancellation stopped.

**Snapping the inset is not the fix — the landing place is.** The first attempt
rounded the inset itself to a length whole in both spaces (4px at 1.25, 3 at
1.333). It works on this output and is wrong in general: whether a subtree
lands whole depends on where its container already is, and the container is
placed by `snap()`, which does not care about logical wholeness. At scale
1.3333 on a 2560 monitor the panel's own left edge lands at 1419.75, and *no*
inset that is a multiple of 3 can fix that.

`Screens.snapTextInset(inset, edge, screen)` takes where the inset starts, in
the window's own coordinates, and returns the inset that lands on a whole
logical pixel — preferring a landing that is a whole device pixel too, so the
outline it places stays crisp, when the scale puts one within 2px. That covers
every scale whose fraction is halves, thirds, quarters or fifths; past that the
nearest whole logical pixel wins, since text is the thing being placed.

Checked arithmetically over 60 combinations — 12 Hyprland-quantized scales
(1.0 … 2.0, including 7/6 and 175/120, both awkward) against five monitor
widths, running the real chain with JS rounding semantics:

| | cards landing fractional |
|---|---|
| inset snapped on its own | 42 of 60 |
| solved for the landing | **0 of 60** |

The inset itself ends up between 23.8 and 28.2 against the designed 26. At 7/6
the landing is whole logically but not in device pixels, and the card's outline
softens instead of its text — the documented order of preference.

**Use it for the last offset in front of text, not everywhere.** Everything
that places an edge, a border or a container still takes `snap()`; only the
inset a text subtree ultimately hangs off needs this, and it needs the
container's *resting* position, never a position mid-animation.

### The other half of it: text steps, plates glide (2026-09-14)

Reported separately, once the panel was crisp at rest: "it looks like the text
of the notification slightly shifts to the right after the animation finishes."
It does, and it is the same rounding seen from the other side. Glyph origins
are rounded to whole device pixels *every frame*, so a moving text subtree
advances in 1px hops; the plate under it carries no such rounding — it is a
layer texture, resampled — so it glides. While the panel is moving quickly the
two are indistinguishable. At the end of a settle they are not: the panel
creeps the last pixel at ~0.1px per frame, and somewhere in that creep the text
takes one 1px step by itself, against a card that looks stationary.

Measured across the last frames of the open, each strip cross-correlated
against the settled frame (device px, positive = still left of home):

| | card's left edge | the text | apart |
|---|---|---|---|
| before | 0.72 → 0.16 | 1.00, held | 0.28 → **0.84** |
| after | 1.04 → 0 | 1.23 → 0 | 0.19, **landing on one frame** |

**Two changes, and neither is about the resting alignment above.** The landing —
the last 2 device pixels of the settle only — snaps the margin to the device
grid, so the plate takes the same hops the text is taking and they arrive
together. And the spring is parked once it is within half a device pixel,
because `FrameSpring.isSettled()` compares a *velocity in px/s* against a
*pixel* epsilon: for a critically damped settle that means it keeps integrating
until the error is ~0.01px, about 130ms of frames that cannot change a single
rendered pixel, which is what gave the lone text step room to happen.

Snapping only the landing, rather than the whole gesture, is deliberate — see
the dead end in `notes/panels.md`: snapped throughout, the slow parts of a
gesture advance one device pixel every ~10ms and read as stepping. The window
is in *device* pixels (`2 / scale`), so it is two hops wide on any output.

**What is irreducible:** the panel still lands with one 1px hop, because text
can only ever sit on whole device pixels. The fix makes the card and its text
take that hop together, which reads as the panel arriving rather than as the
text sliding inside it.

