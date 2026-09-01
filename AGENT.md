# AGENT.md

Notes for whoever works on this repo next. This is a Quickshell bar meant
as a drop-in replacement for an existing Waybar setup — same look, same
modules, same per-monitor layout. Not meant to grow new features beyond
what Waybar already does unless asked.

## Source of truth

Waybar is the design spec — match these files, don't invent a new look:

- `~/.config/waybar/config` — per-output bar definitions.
- `~/.config/waybar/config.d/common.json` — per-module config (formats, icons, intervals).
- `~/.config/waybar/style.css` — the visual spec: colors, padding, radii, borders. Wins on any doubt.
- `~/.config/waybar/scripts/weather/` — external weather script (`Weather.qml` reimplements it natively).
- `/tmp/Waybar` — Waybar's C++ source, useful when CSS/config alone doesn't explain a module's behavior.

If Waybar's config/style changes, re-diff this repo's modules against it,
not against old screenshots.

## Layout

```
shell.qml             Variants{ model: Quickshell.screens } → one Bar per
                      output; also owns the per-screen layout config (which
                      modules, which screens get which set)
modules/Bar.qml       PanelWindow per output; left/center/right groups,
                      rendered generically from the {left,center,right}
                      `layout` shell.qml hands it — no per-module or
                      per-screen special-casing lives here
modules/*.qml         one file per Waybar module — thin views, no owned
                      subprocesses/network/timers for cross-monitor state
services/*.qml        pragma-Singleton types holding state + the actual
                      subprocess/network I/O for anything system-wide
                      (BacklightService, MpdService, SwayNCService,
                      WeatherService) — one poll/subscription/fetch cycle
                      for the whole process regardless of monitor count
shared/Theme.qml      pragma-Singleton palette + metrics, mirrored from
                      style.css — shared process-wide, not one instance
                      per output
shared/Tooltip.qml    reusable hover popup
shared/ModuleGroup.qml the left/right pill-shaped module group (flush
                      against a screen edge, rounded only on the
                      center-facing side); used twice from Bar.qml with
                      edge: Qt.LeftEdge/Qt.RightEdge
shared/ModuleLoader.qml Repeater delegate for one named module: resolves a
                      module name to a Component and applies the
                      `contentVisible` Loader-visibility workaround
shared/WeatherIcons.js glyph/description lookup table for weather codes
```

## Per-screen module layout

Which modules appear where is configured in `shell.qml`, not hardcoded in
`Bar.qml`: `mainScreens` lists monitor names (check with `hyprctl monitors
-j`) that get `mainLayout`; every other screen gets `defaultLayout`. Each
layout is a plain `{left, center, right}` object of module-name strings.
`shell.qml` calls `layoutFor(modelData.name)` per screen and passes the
result into `Bar { layout: ... }`.

`Bar.qml` only knows how to render whatever list it's handed: a
`moduleComponents` string -> `Component` map (add a new module there to
make it placeable) plus a `Repeater`/`Loader` per group that instantiates
whatever's named in `layout.left`/`.center`/`.right`. A module only gets
instantiated at all if some screen's layout actually names it — this is
what keeps the expensive modules (Tray/Privacy/Weather: icon textures,
hover popups, network) from paying their cost on screens that don't list
them, the same way the old `isDp1`-gated `Loader`s did.

Currently mirrors the original `~/.config/waybar/config` split: every
output gets `mpd`, `submap`, `workspaces`, `backlight`, `volume`, `swaync`,
`clock`; only `DP-1` (in `mainScreens`) additionally gets `tray`, `privacy`,
`weather`.

**Left/right group edge-spacing tuning is order-sensitive.** `leftGroup`'s
comment about the first module's glyph bearing covering
`moduleOuterMargin`, and `rightGroup`'s comment about needing it explicitly,
both assume the *default* left order (`mpd`, `submap`) and right order
(`clock` last). Reordering a screen's layout so a different module lands at
the flush screen edge may need re-tuning those margins for that edge.

## Style-mapping notes

- **Bar has real extra height below the content, not an overlay.** Waybar's
  border-bottom is genuine added height, not painted over the content — see
  `implicitHeight: theme.barHeight + theme.barBorderHeight` in `Bar.qml`.

- **`.modules-left`/`.modules-right` are flush half-stadium shapes**, not
  floating capsules — rounded only on the side facing center. Needs Qt
  6.7+'s per-corner `Rectangle` radius properties, not a single `radius`.

- **Workspace color has three states.** Default = teal (`workspaceBg`),
  `.urgent` = pink, `.active`/`.focused` = accent, `.empty` = cream. A
  populated non-focused workspace must stay teal, not default to cream.

- **Quickshell's Hyprland `active` ≠ Waybar's "active" class.** Quickshell
  `active` = focused per-monitor (can be true on N monitors at once);
  `focused` = the one true system-wide focused workspace, matching Waybar's
  `isActive()`. Use `modelData.focused` for the single accent highlight.

- **`HyprlandWorkspace` has no `windows`/`empty` property.** Read
  `modelData.lastIpcObject.windows` instead.

- **The `button.visible.current_output` box-shadow rule is dead code here**
  — only fires for `sway/workspaces`, never `hyprland/workspaces`. Don't
  replicate it.

- **`.modules-center`'s pill caps are cream, fixed 15px on the container**,
  not a margin around the buttons — see `Workspaces.qml`'s `capWidth`.

- **Every `Text {}` needs `renderType: Text.NativeRendering`.** The default
  SDF renderer shows visible chromatic fringing on this machine; native
  rendering matches Waybar's crisp Pango/cairo text. No global setting
  exists for this — every `Text` needs it explicitly.

- **`font.family` can't take a CSS-style comma fallback string.** QML only
  accepts one family; Qt fuzzy-resolves a joined string down to just the
  icon font, leaving Latin text falling back to some other, narrower font.
  Fix in use: `Theme.fontFamily` = `"Inter Variable"` alone, relying on
  Qt's automatic per-glyph fallback for Nerd Font icon codepoints
  (`font.families`, the correct fix, isn't registered on this Qt build's
  Text type — retry if that ever changes).

- **`Workspaces.qml`'s button width needs a GTK-chrome allowance beyond
  style.css.** CSS gives 18px padding, but real buttons measure ~34px —
  GTK's own default chrome, not derivable from the stylesheet. Formula:
  `Math.round(Math.max(label.implicitWidth + 18, 34))`, empirical.

- **`.modules-left`/`.modules-right`'s 12px border is one-sided**, only on
  the inner/center-facing edge. Anchor the inner RowLayout to the flush
  edge, not `centerIn`, or the flush edge gets a spurious extra 12px too.

- **Screen edges aren't symmetric by construction.** Every module's shared
  CSS rule (`padding: 0 6px; margin: 0 4px;`) needs both halves modeled —
  modules only accounted for the 6px padding, missing the 4px margin. This
  only shows up on the two modules flush against the true screen edge
  (`Mpd` left, `Clock` right) — elsewhere `RowLayout` spacing hides it.
  Fixed via `theme.moduleOuterMargin` (4px), added only where a flush
  module actually needs it (`rightGroup` in `Bar.qml`; not `leftGroup`,
  since Mpd's own icon glyph bearing already covers it — adding it there
  would overshoot). **Lesson:** a CSS rule can have multiple additive parts;
  modeling only one can still look right almost everywhere by luck, and
  only fail at edge modules with no neighbor to hide behind.

- **A hover popup that should stay open when the cursor moves onto it
  needs a grace-period timer**, not a plain `anchorHover.containsMouse ||
  popupHover.containsMouse` OR — the popup is a separate surface a few px
  away, so a plain OR closes it before the cursor arrives. Fixed with a
  ~200ms `Timer` that only starts once both report `containsMouse: false`.
  Used independently in both `Tooltip.qml` and `Weather.qml`'s popup.

- **`Layout.fillWidth: true` on a `Repeater` delegate that's itself a
  `Layout`** (e.g. `Weather.qml`'s hourly columns) does nothing unless
  `Layout.maximumWidth` is also overridden — QtQuick.Layouts auto-clamps a
  nested Layout's `maximumWidth` to its own `implicitWidth`. Only
  `maximumWidth` is load-bearing; `minimumWidth`/`preferredWidth` only
  affect how space splits between columns. Diagnosed via a debug
  `Rectangle` to see which nesting level actually refused to grow.

- **Adjacent same-color `Rectangle`s in a `RowLayout` can show a 1px seam**
  from fractional-width rounding error. `Workspaces.qml` rounds its
  `Layout.preferredWidth` and disables `antialiasing` to avoid it.

## QML gotchas hit in this repo

- **A binding that only *calls* `Repeater.itemAt()`, without also *reading*
  a real NOTIFY property (e.g. `Repeater.count`) in the same expression,
  evaluates once and then stays stale forever** — no warnings, even at
  `-vv`. QML's dependency tracking only hooks into property reads, not
  method calls. Hit in `Workspaces.qml`'s sliding indicator: fixed with
  `repeater.count > index ? repeater.itemAt(index) : null`, since `count`
  has a real `countChanged` signal. Diagnosed via a bright debug
  `Rectangle` behind the suspect item to confirm the binding never fired.

- **A `Loader` with `active: false` still reserves `RowLayout` spacing on
  both sides unless it's also `visible: false`.** The Loader item itself
  defaults `visible: true` even when inactive/zero-width; `RowLayout` only
  excludes spacing for genuinely invisible children. Fixed in `Bar.qml` by
  adding `visible: active` to each DP-1-only Loader.

- **Never bind a `Loader`'s own `visible` to its loaded item's `visible`
  (`visible: item.visible`) — it's a permanent deadlock, not just a
  startup-order glitch.** Sequence: `item` starts `null`, so the binding
  evaluates `visible: false` on the Loader itself *before* anything loads.
  Once `sourceComponent` creates the item and parents it under the
  (already-`visible: false`) Loader, Qt Quick cascades the ancestor's false
  `visible` down into the child — the child's own `visible` *getter* now
  permanently returns `false` regardless of its local condition, because an
  invisible ancestor overrides it. That false reading feeds straight back
  into the Loader's binding, which stays false forever; the item's local
  condition flipping true later never fires a change (the cascaded getter
  never stops returning false), so it never recovers. No warning is ever
  printed — `implicitWidth`/`width` keep computing correctly throughout,
  which is what makes it easy to mistake for "should just be a timing
  issue" instead of a real deadlock. This exact pattern shipped in the
  original `Privacy.qml` Loader (`visible: item ? item.visible : false`) —
  meaning the mic indicator most likely never actually appeared, silently,
  since nobody had reason to stare at an idle mic icon. Diagnosed by
  hardcoding the Loader's `visible: true` and confirming `item.visible` then
  read correctly (proving the cascade, not something else, was the cause).
  **Fix:** give the module a plain, non-`visible` bool (e.g.
  `contentVisible`) mirroring the same condition, and have the Loader read
  *that* instead — see `Mpd.qml`'s `contentVisible` and `Bar.qml`'s
  `moduleVisible(item)`.

- **A Repeater delegate type that declares *any* `required property` stops
  receiving the legacy ambient `modelData`/`index` context properties
  entirely** — Qt switches that delegate to required-property-only
  binding, so an unqualified `modelData` reference inside it (or in the
  expression assigning one of its other properties) silently falls through
  to an unrelated ancestor's `modelData` instead (in this repo: the bar's
  own screen, from shell.qml's `Variants`), rather than the Repeater's own
  item. No warning — just wrong data, and `console.warn`-style guards see
  the wrong value passed in. Hit in `shared/ModuleLoader.qml` (needs
  `required property var resolveComponent` for the injected callback):
  fixed by also declaring the model value itself as `required property
  string modelData` (Qt's documented mechanism for exposing a plain-array
  Repeater model to a required-property delegate), instead of relying on
  the bare identifier or a differently-named prop. Diagnosed by
  `console.warn`-ing the resolved name and seeing a screen object instead
  of a module-name string.

## Intentional enhancements beyond Waybar parity

Requested explicitly as visual polish, not bugs to "fix" back to instant:

- Every module eases `implicitWidth` (`Theme.qml`'s `resizeDuration`) on
  content-size changes, which reflows the whole bar smoothly for free.
- `Workspaces.qml`'s focus highlight is a single shared `selection`
  Rectangle that slides/resizes between delegates, with labels kept as a
  separate static top layer so only the square moves.

## Known, deliberate deviations from Waybar

- **`Privacy.qml`** only replicates the mic indicator; screen-share
  detection isn't implemented (no simple Pipewire signal for it).
- **`Mpd.qml`** polls `mpc` on a timer since mpd isn't exposed over MPRIS
  here and Quickshell has no built-in mpd client.
- **`Weather.qml`** natively reimplements the bar icon+temperature and a
  broadly similar popup, rather than shelling out to Waybar's script —
  visual parity, not byte-identical format.
- **`Tray.qml`'s icon order won't reliably match Waybar's** — neither app
  sorts tray icons without an explicit `order` config, so it's just
  registration order and varies per restart. Not a bug to chase.

## How to visually compare against Waybar

Both can't run at once (same layer/output), so:

```sh
pkill waybar
qs -p shell.qml &
```

Screenshot a specific output with `grim` (get geometry first, since `-o`
and `-g` are mutually exclusive):

```sh
hyprctl monitors -j
grim -g "2560,0 3840x28" out.png
```

Restore Waybar when done (`pkill -f "qs -p shell.qml"; waybar &`).

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
but Waybar's actual config (`config.d/common.json`) uses 14px icons with
20px spacing — more than double. Fixed both values to match.

**Lesson:** per-glyph diffing isn't sufficient — it can't catch a spacing
deficit spread evenly across many small gaps. Check the *aggregate* group
width first (sample where a column's color transitions between bar/group
background), before zooming into individual icons. Also check Waybar's
JSON config, not just style.css — some values (tray spacing/icon-size)
only live there.

**Follow-up fix (2026-08-30):** `Tray.qml` was still missing style.css's
shared `padding: 0 6px` rule (a comma-list selector covering `#tray` too,
easy to miss by grepping `#tray` alone). Fixed by widening `implicitWidth`
to `row.implicitWidth + 12`.

**Scaling note:** `DP-1` runs at Hyprland `scale: 1.25` — `grim -g`
geometry is logical px, but the output PNG is physical px, so raw
pixel-count comparisons need the scale factor divided back out.

**Capture note:** always grab a few px of vertical slack past the nominal
bar height — an exact-height crop can appear to be missing a bottom border
that's actually just outside the capture (the window is 1px taller than
`barHeight + barBorderHeight` due to `margins.bottom: 1`).

**Working method:** capture the same geometry from both apps, diff the
aggregate group-edge position first, then crop matching sub-regions to
compare individual icons at zoom. For gap measurement within a crop, a
brightness-threshold column scan (cluster non-background columns into
per-glyph segments) beats raw pixel diffing, since antialiasing produces
false positives pixel-by-pixel.
