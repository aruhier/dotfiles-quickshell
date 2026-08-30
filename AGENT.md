# AGENT.md

Notes for whoever (human or agent) works on this repo next. This is a
Quickshell bar meant to be a drop-in visual replacement for an existing
Waybar setup — same look, same modules, same per-monitor layout. It is not
meant to grow new features beyond what Waybar already does unless asked.

## Source of truth

Waybar is the design spec. Don't invent a new look — match these files:

- `~/.config/waybar/config` — per-output bar definitions (`modules-left/center/right`, which outputs get which bar).
- `~/.config/waybar/config.d/common.json` — per-module Waybar config (formats, icons, intervals).
- `~/.config/waybar/style.css` — the actual visual spec: colors, paddings, radii, borders. When in doubt about a color or shape, this file wins.
- `~/.config/waybar/scripts/weather/` — the external weather script Waybar shells out to (this repo's `Weather.qml` reimplements it natively instead, see below).
- `/tmp/Waybar` — Waybar's own C++ source. Useful when the CSS/config alone doesn't explain a module's behavior (e.g. what "empty" or "active" actually mean for a given module — grep `src/modules/**`).

If Waybar's config/style changes, this repo's modules should be re-diffed
against it, not just against old screenshots.

## Layout

```
shell.qml            Variants{ model: Quickshell.screens } → one Bar per output
modules/Bar.qml       PanelWindow per output; left/center/right groups
modules/*.qml         one file per Waybar module (Clock, Mpd, Workspaces, ...)
shared/Theme.qml      the palette + metrics, mirrored from style.css — single
                      source of truth for colors *and* magic-number layout
                      constants (padding, cap widths, ...) so modules never
                      hardcode hex or bare pixel numbers
shared/Tooltip.qml    reusable hover popup (Waybar's GTK tooltip equivalent)
shared/WeatherIcons.js glyph/description lookup table for weather codes
```

`Bar.qml` mirrors `~/.config/waybar/config`'s two bar definitions: every
output gets `mpd`, `hyprland/submap`, `hyprland/workspaces`, `backlight`,
`pulseaudio`, `custom/swaync`, `clock`; only `DP-1` additionally gets `tray`,
`privacy`, `custom/weather` (`barWindow.isDp1` gates those). If the Waybar
config's per-output module list changes, update the `visible: barWindow.isDp1`
conditions in `Bar.qml` to match.

## Style-mapping notes (things that aren't obvious from a glance at the CSS)

- **The bar has real extra height below the content, not an overlay.**
  Waybar's `#waybar > box { border-bottom: 3px solid ... }` adds height —
  the 22px content area (`config`'s `"height": 22`) sits *above* a separate
  3px border strip, they don't overlap. `Bar.qml` reflects this:
  `implicitHeight: theme.barHeight + theme.barBorderHeight`, with an inner
  `Item { height: theme.barHeight }` holding all the groups, and the border
  `Rectangle` anchored below it. If a group Rectangle instead fills the
  *whole* window height, it paints over the border stripe along its width —
  easy mistake, hard to notice without zooming into a screenshot.

- **`.modules-left` / `.modules-right` are not floating capsules.** They're
  flush against the screen edge and rounded only on the side facing the
  center (a "fin"/half-stadium shape), via CSS's
  `border-{top,bottom}-{left,right}-radius`. In QML this needs Qt 6.7+'s
  per-corner `Rectangle` properties (`topLeftRadius`, `bottomRightRadius`,
  etc.) — a single symmetric `radius` gives a floating pill instead, which
  is visibly wrong (compare against a real Waybar screenshot: the outer
  edge must be perfectly square against the screen edge, no margin).

- **Workspace color has three states, not two.** `style.css` default-styles
  *every* `#workspaces button` with `workspaceBg` (teal), then overrides:
  `.urgent` → pink, `.active`/`.focused` → accent (bold), `.empty` → cream.
  "Empty" means the Hyprland workspace has 0 windows
  (`Workspace::isEmpty()` in `/tmp/Waybar/src/modules/hyprland/workspace.cpp`
  is literally `m_windows == 0`). A workspace with windows that isn't
  focused must still render as **teal**, not cream — defaulting everything
  non-focused to the empty color is a real, visible bug (it makes populated
  background workspaces look empty).

- **Quickshell's Hyprland workspace `active` ≠ Waybar's "active" class.**
  Quickshell: `active` = "focused on its own monitor" (true for one
  workspace *per monitor* simultaneously — with `all-outputs: true` across
  N monitors that's N highlighted workspaces at once). `focused` = "active
  on the monitor that is itself focused" (true for exactly one workspace,
  system-wide). Waybar's `hyprland/workspaces` `isActive()` matches
  Quickshell's `focused`, not `active`. Use `modelData.focused` for the
  single accent/bold highlight, or every monitor's last-active workspace
  lights up as if it were the current one.

- **Quickshell's `HyprlandWorkspace` has no `windows`/`empty` property.**
  Read `modelData.lastIpcObject.windows` (the raw `hyprctl workspaces -j`
  blob Quickshell wraps) to replicate Waybar's empty/populated distinction.

- **The `button.visible.current_output` box-shadow rule in `style.css` is
  dead code for this setup.** It only ever fires for `sway/workspaces`
  (which sets a `current_output` class); `hyprland/workspaces` sets
  `active`/`empty`/`urgent`/`visible`/`hosting-monitor` instead, never
  `current_output`. Don't try to replicate that red inset border — a real
  Waybar screenshot on this Hyprland setup never shows it.

- **`.modules-center`'s pill caps are cream, not teal**, and are a fixed
  15px `border-left`/`border-right` on the *container*, independent of the
  buttons inside. The container's own fill matters (not just a thin margin
  around the button row) — see `Workspaces.qml`'s `capWidth`.

- **Every `Text {}` needs `renderType: Text.NativeRendering`.** QML's
  default text renderType (`Text.QtRendering`, distance-field/SDF) shows up
  on this machine as visible red/blue chromatic fringing on every glyph —
  letters *and* Nerd Font icon glyphs alike, on every monitor, independent
  of color management (confirmed by comparing waybar vs quickshell
  screenshots pixel-by-pixel: rectangle fill colors were exact matches,
  only text edges differed). `Text.QtRendering` does *not* fix it;
  `Text.NativeRendering` does — it bypasses the SDF glyph atlas and
  rasterizes via FreeType directly per frame, matching Waybar's crisp
  Pango/cairo text. Every module's `Text` elements have this set explicitly
  (no app-wide QML equivalent of `QQuickWindow::setTextRenderType()`
  exists, so it can't be set once globally). If a new `Text {}` is added
  anywhere, it needs this too or it will visibly fringe on this system.

- **`font.family` can't take a CSS-style comma-joined fallback string.**
  style.css's `font-family: Symbols Nerd Font Mono, Inter Variable, Material
  Design Icons Desktop` is a fallback *cascade* — Pango picks per-character
  from the list. QML's `font.family` only accepts a single family name;
  feeding it the whole comma-joined string doesn't give a cascade, Qt
  fuzzy-resolves it to just `"Symbols Nerd Font Mono"` (confirmed via
  `fc-match` — it silently ignores the rest of the string). That font is
  icon-glyphs-only (`fc-query`'s charset has no `0061`/'a'), so every plain
  Latin-text `Text {}` (workspace labels, clock, mpd title, ...) was quietly
  falling back to *some other* installed font for the actual letters —
  narrower than Waybar's real `Inter Variable`, which made whole modules
  (worst offender: `Workspaces.qml`, ~277px vs Waybar's ~365px measured
  total) render visibly smaller/tighter than Waybar despite the CSS
  numbers matching. `font.families` (Qt 6.1+'s real list property for this)
  is *not* registered on this build's QML Text font value type — assigning
  it throws `Cannot assign to non-existent property "families"` at load
  time. The fix in use: set `Theme.fontFamily` to plain `"Inter Variable"`
  only, and rely on Qt's own automatic per-glyph fallback (confirmed
  working: Nerd Font icon codepoints still render correctly even though
  Inter Variable doesn't contain them) to reach the icon font for PUA
  codepoints. If a future Qt build here does register `font.families`,
  switching to it directly (list: `["Inter Variable", "Symbols Nerd Font
  Mono", ...]`) would be the more correct fix — worth retrying then.

- **`Workspaces.qml`'s per-button width needs a GTK-chrome allowance
  beyond what style.css states.** `#workspaces button`'s CSS gives 18px of
  padding (10 left + 8 right) — but a real Waybar screenshot shows *every*
  single-character workspace button at a consistent ~34px regardless of
  which glyph it is (measured 3 separate same-color button blocks in one
  screenshot, all within 1px of 34px/button). The ~9-16px gap beyond
  `label.implicitWidth + 18` is GTK's own default button chrome (Adwaita's
  built-in min-width/border, baked into libgtk3's compiled-in theme
  resources — not present anywhere in style.css, so it can't be derived
  from the stylesheet, only measured). The button width formula is
  `Math.round(Math.max(label.implicitWidth + 18, 34))` — the 34 is an
  empirical constant from that screenshot measurement, not a CSS value. If
  Waybar's GTK theme ever changes, re-measure rather than trust this number
  blindly.

- **`.modules-left`/`.modules-right`'s 12px CSS border is one-sided, not a
  symmetric padding.** `border-width: 0 12px 0 0` (modules-left) means the
  extra space is *only* on the inner/center-facing edge; the outer/flush
  edge gets none. An earlier version of `Bar.qml` gave both groups a
  symmetric `implicitWidth: row.implicitWidth + 24` centered via
  `anchors.centerIn`, which put a spurious 12px of padding on the flush
  edge too (confirmed: pushed the mpd icon ~20px further from the screen
  edge than Waybar's). Fixed by anchoring the inner `RowLayout` to
  `anchors.left`/`anchors.right` (flush side) instead of centering, with
  `implicitWidth: row.implicitWidth + 12` (only the inner pad).

- **The bar's true left and right screen edges are not symmetric by
  construction, and can silently drift apart.** Every module in style.css's
  shared `#clock, #mpd, ... { padding: 0 6px; margin: 0 4px; }` rule gets
  10px of blank space on *each* side (6 padding + 4 margin) — but
  `Mpd.qml`/`Clock.qml` (etc.) only ever modeled the 6px padding half
  (`implicitWidth: label.implicitWidth + 12`), never the 4px margin half.
  This was invisible for months because it only matters at the two modules
  that sit flush against the bar's true outer edge with zero group-level
  compensation (`Mpd` on the left, `Clock` on the right — see the note
  above) — everywhere else, `RowLayout`'s `spacing: 10` between modules
  papers over the gap. On the left edge it stayed invisible for a different
  reason too: the pause/play icon glyph (mpd) has enough of its own
  left-side bearing baked into the font that its ink lands ~10px from the
  edge *anyway*, no margin needed — pure coincidence of that specific
  glyph's shape. On the right edge, the last character is a plain digit
  (clock's `hh:mm`) with near-zero right-side bearing, so the missing 4px
  showed up directly as a visibly smaller gap (measured: 7px vs. Waybar's
  10px). Caught by the user eyeballing the two edges side by side; confirmed
  with a pixel measurement (column scan for the first/last non-`groupBg`
  pixel, same method as the tray fix below) against a live Waybar capture at
  the identical geometry, which showed a clean symmetric 10px/10px.
  **Fixed by adding `theme.moduleOuterMargin` (4px, named after the CSS
  property it represents) only where a flush module actually needs it** —
  `rightGroup`'s `implicitWidth` and `rightRow`'s `anchors.rightMargin` in
  `Bar.qml` — deliberately *not* added to `leftGroup`, since Mpd already
  measures correctly without it and adding it there would overshoot to
  ~14px. **Lesson:** a per-module CSS rule can have multiple additive parts
  (here, padding *and* margin); modeling only one of them can still "look
  right" almost everywhere by sheer luck of RowLayout spacing or a
  particular glyph's bearing, and only fail visibly at an edge case (here,
  the two modules with no neighbor to hide behind). When verifying box-model
  fidelity, check the literal screen-edge modules specifically, not just
  interior gaps — and re-derive the fix per-glyph/per-side by measurement,
  not by assuming a symmetric formula will look symmetric.

- **A hover popup (`shared/Tooltip.qml`, and `Weather.qml`'s own bespoke
  one) that should "stay open when the cursor moves onto it" needs a
  grace-period timer, not just `anchorHover.containsMouse ||
  popupHover.containsMouse`.** The popup is a separate `PopupWindow`
  surface, positioned a few px below the anchor (`onAnchoring`'s `+ 4`).
  With a plain OR: the instant the cursor leaves the anchor, `visible`
  re-evaluates to false (the popup's own `containsMouse` is still false —
  the cursor hasn't arrived yet) and the popup unmaps itself *before* the
  cursor crosses that gap, so its `MouseArea` never gets a chance to see the
  cursor arrive — it just looks like the popup closes the moment you try to
  move onto it. Fixed by delaying the close instead of doing it immediately:
  a `Timer` (~200ms) starts counting only once *both* the anchor and the
  popup report `containsMouse: false`, and gets stopped/reset the moment
  either one reports true again — a normal-speed cursor crossing a few px
  comfortably beats 200ms, so the popup never actually closes mid-transit.
  Both `Tooltip.qml` and `Weather.qml`'s popup need this same pattern
  independently (they don't share an implementation) — if a third module
  ever grows its own hover popup, it needs it too.

- **Adjacent same-color `Rectangle`s in a `RowLayout` can show a 1px seam.**
  If sibling widths are fractional (e.g. `label.implicitWidth + 18` where
  `implicitWidth` is rarely an integer), `RowLayout` accumulates rounding
  error across cells and can leave a stray 1-device-pixel gap between two
  buttons where the parent's own fill color peeks through — invisible at
  1x but an obvious thin line once zoomed. `Workspaces.qml`'s delegate
  rounds its `Layout.preferredWidth` (`Math.round(...)`) to avoid this, and
  also sets `antialiasing: false` (buttons are unrounded and sit flush, so
  there's no benefit to it, only a softened shared edge to avoid).

## Known, deliberate deviations from Waybar

- **`Privacy.qml`** only replicates the `audio-in` (mic) privacy indicator.
  Waybar's `screenshare` indicator isn't implemented — Quickshell has no
  simple Pipewire-graph signal for "an app is screen-sharing"; it would need
  an xdg-desktop-portal ScreenCast/DBus watcher.
- **`Mpd.qml`** polls `mpc` (subprocess) on a timer instead of using a
  built-in MPD client, since Quickshell has none and this machine's MPD
  isn't exposed over MPRIS.
- **`Weather.qml`** is a native reimplementation (fetches Open-Meteo
  directly, renders its own popup) rather than shelling out to
  `~/.config/waybar/scripts/weather/get_weather.rb` and using a pango
  tooltip. Visual target is icon+temperature parity in the bar and a
  broadly similar "current + forecast" popup, not a byte-identical format.
- **`Tray.qml`'s icon order won't reliably match Waybar's.** Both just
  render `SystemTray`/SNI items in whatever order they're reported in —
  neither app sorts them (Waybar's `Tray::reorderBox()` only sorts by an
  explicit per-app `order` from its `tray.icons` config, which this
  Waybar config doesn't set, so it's really insertion/registration order).
  Confirmed by restarting Waybar itself mid-session: the icon order changed
  on every single restart. Don't chase this as a bug — there's no stable
  "correct" order to replicate.

## How to visually compare against Waybar

Both can't usefully run at once (they'd overlap on the same layer/output),
so:

```sh
pkill waybar                      # or your normal way of stopping it
qs -p shell.qml &                 # from this repo's root
```

Screenshot a specific output's bar strip with `grim` (note: `-o` and `-g`
are mutually exclusive, so look up output geometry first):

```sh
hyprctl monitors -j                              # get x,y,width for each output
grim -g "2560,0 3840x28" out.png                 # bar strip only, not full screen
```

When done, restore Waybar (`pkill -f "qs -p shell.qml"; waybar &`).

If you instead grab a full-output screenshot (`grim -o <name> full.png`) and
crop it in stages with ImageMagick, add `+repage` after each `-crop` before
cropping again — otherwise the file keeps the original canvas offset baked
in and a second `-crop` on the already-cropped file silently measures from
the *original* image's coordinates, not the cropped one's.

Monitor layout is machine-specific and can change; re-check with
`hyprctl monitors -j` rather than trusting old notes. At time of writing:
`DP-2` at (0,0) 2560×1440, `HDMI-A-1` at (5632,0) 2560×1440 (rotated),
`DP-1` at (2560,0) 3840×2160 — `DP-1` is the one with tray/privacy/weather.

## Full visual re-verification (2026-08-29, two passes)

**First pass** (crude, wrong conclusion): did a side-by-side pixel
comparison of every module on all three outputs and concluded "no visual
regressions found." That conclusion was wrong — it missed a real, visible
bug (below) because the comparison crops happened to sample individual
glyphs (bell, volume-mute, clock text) that matched, without ever measuring
the *aggregate* width of the whole `modules-right` group. A user follow-up
("icons on quickshell are smaller, gaps on the right are smaller") is what
caught it.

**Second pass** (found the bug): `Tray.qml` hardcoded `spacing: 8` and
16px icons (`Layout.preferredWidth`/`Layout.preferredHeight`/
`implicitSize: 16`), but Waybar's actual tray config
(`~/.config/waybar/config.d/common.json`, `"tray": {"icon-size": 14,
"spacing": 20}`) uses 14px icons with **20px spacing** — more than double
Quickshell's. Across 5 tray icons (4 gaps) that's a ~48 logical-px deficit,
which is most of the ~60 logical-px (~75 physical-px at DP-1's 1.25 scale)
narrower `modules-right` group width that was actually measured (see method
below). Fixed both values in `Tray.qml` to match: `spacing: 20`,
icon size `14`. Re-measured after the fix: the group's left edge moved from
being ~60 logical px short of Waybar's to within ~14 logical px of it — the
remaining ~14px is normal per-glyph rendering variance (different icons in
the tray have different intrinsic bounding-box padding in the Nerd
Font/SNI-icon rendering; not a further bug to chase).

**Lesson for next time:** per-glyph pixel-diffing (crop one icon, zoom,
eyeball) is necessary but *not sufficient* — it can't catch a systemic
spacing deficit that's spread evenly across many small gaps, because each
individual gap still "looks about right" in isolation. The real check is
**aggregate**: measure the *group's total rendered width* (or equivalently,
where its left edge lands relative to the screen's right edge) and compare
that single number against Waybar's. Do this first, before zooming into
individual icons — it's cheap and it's what actually caught the bug.
Method: find the x where a column's color transitions from bar background
(`#2d2d2d`) to group background (`#424242`), sampled at a y-row inside the
group's flat (non-corner) region (avoid y near the very top/bottom, where
the rounded-corner curve pushes the transition point further right/left
than the group's true edge) — do this once per app, same output, and diff
the two x values directly. When per-module config values exist on the
Waybar side (`config.d/common.json`), diff against those directly instead
of just the CSS — spacing/icon-size for `tray` (and potentially other
modules) live in the JSON config, not `style.css`, and are easy to miss if
you only ever grep the stylesheet.

**Follow-up fix (2026-08-30):** even after the spacing/icon-size fix above,
`Tray.qml` still had a gap wrong: `implicitWidth: row.implicitWidth` had no
allowance for `style.css`'s shared per-module rule (`#tray, #mpd, #privacy,
#custom-swaync, #custom-weather, ... { padding: 0 6px; margin: 0 4px; }`,
around line 100 of `style.css`) that every one of these single-icon-ish
modules gets, including `#tray`. That rule is easy to miss because it's a
comma-list selector shared across many modules, not a `#tray`-specific
block — grepping for `#tray` alone skips it. Fixed by widening to
`row.implicitWidth + 12` (the `0 6px` padding on both sides), which lines
the tray's left edge up with e.g. mpd's right-side gap. **Lesson:** when
diffing a module's box model against `style.css`, always check for a
shared/grouped selector matching that module's ID in addition to any
module-specific block — `grep -n '#modulename'` alone misses rules where
the module is one name in a longer selector list.

Also worth knowing for scaled outputs: **DP-1 runs at Hyprland `scale:
1.25`**, not 1 — `hyprctl monitors -j` now reports `"scale": 1.25` for it
(re-check this, it's monitor config and can change). `grim -g "X,Y WxH"`
takes the geometry in *logical* pixels (matching Hyprland's own coordinate
space) and returns a PNG at the *physical* resolution — e.g. requesting
`3840x30` on DP-1 actually returns a `4800x37` image (×1.25). This isn't a
bug in the comparison method (both apps' composited output get the same
treatment), but it means literal pixel-count math (like the tray deficit
above) needs the scale factor divided back out to get logical px, and
`hyprctl monitors -j`'s `x`/`y` fields for monitor position are also in
this same logical space (not the physical `width`/`height` fields) — that's
why `DP-1` at logical x=2560 with physical width 3840 @ scale 1.25 (logical
width 3072) puts the next monitor's `x` at 5632, not 6400.

One methodology trap from the first pass, still valid and worth recording:
an early crop grabbed only `3840x25` (`barHeight + barBorderHeight`) and
appeared to show the Quickshell bar missing its teal bottom border entirely
vs. a Waybar capture that had it — looked like a real bug. It wasn't: the
window's actual rendered height is 1px taller than the nominal 25 (see
`margins.bottom: 1` in `Bar.qml`), so the border row was just outside a
25px-tall grim capture. Capturing at `3840x30` (or any height with slack)
shows the border in both. **Always capture with a few px of vertical slack
past the nominal bar height before concluding a bottom-edge element is
missing.**

Working method for a future comparison pass: run one app, `grim -g "<x>,<y>
<w>x30"` (note the +5px slack from the trap above; remember the geometry is
logical px and the output PNG will be physical px if the output is scaled),
swap apps, capture the same geometry, then **first** diff the aggregate
group-edge position (method above) for each left/center/right group, and
**only then** `magick <img> -crop WxH+X+Y +repage -resize N%` on matching
sub-regions from both to eyeball individual icons at high zoom. For
icon-level gap measurement within a crop, a brightness-threshold column
scan (flag a column as "content" if any pixel's R+G+B sum exceeds the
background by a wide margin, then cluster columns separated by small gaps
into per-glyph/per-module segments) beats trying to diff raw pixels, since
text antialiasing produces false positives pixel-by-pixel.
