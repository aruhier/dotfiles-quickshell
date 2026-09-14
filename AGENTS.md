# AGENTS.md

Notes for whoever works on this repo next. This is a Quickshell status bar
with a fixed visual identity (dark bar, teal accent, pill-shaped module
groups) and a fixed per-monitor module layout. Not meant to grow new
features beyond what's already here unless asked.

## Source of truth

The visual spec lives in the code itself:

- `shared/Theme.qml` — the palette + metrics singleton: colors, padding,
  radii, border widths, font sizes, animation springs. Wins on any doubt
  about a visual value.
- This file — behavioral notes, gotchas, and the reasoning behind
  non-obvious choices that aren't self-evident from the code.

## Layout

All cross-file imports go through Quickshell's synthesised `qs` module
(`import qs.shared`, `import qs.services`, `import qs.shared.animations`, …),
which is rooted at this config directory — not relative-path imports like
`import "../shared"`. A file that uses a type from its *own* directory imports
that directory too, even though QML would resolve it implicitly: without the
explicit import `scripts/lint.sh` can't tell a `pragma Singleton` from a type
and reports every property on it as missing. Only the `.js` import in
Weather.qml stays a relative path (JS resources have no module form here).

```
shell.qml             Variants{ model: Quickshell.screens } → one Bar per
                      output; also owns the per-screen layout config (which
                      modules, which screens get which set)
modules/Bar.qml       PanelWindow per output; left/center/right groups,
                      rendered generically from the {left,center,right}
                      `layout` shell.qml hands it — no per-module or
                      per-screen special-casing lives here
modules/*.qml         one file per bar module — thin views, no owned
                      subprocesses/network/timers for cross-monitor state.
                      Almost all of them are `BarModule`s (see below)
services/*.qml        pragma-Singleton types holding state + the actual
                      subprocess/network I/O for anything system-wide
                      (AudioService, BacklightService, LockKeysService,
                      MpdService, MprisService, NotificationService,
                      OsdService, WeatherService) — one
                      watch/subscription/fetch cycle for the whole process
                      regardless of monitor count
shared/Theme.qml      pragma-Singleton palette + metrics — shared
                      process-wide, not one instance per output
shared/BarModule.qml  base type for a bar module: eased width (contentWidth +
                      padding through a FrameSpring), bar-height sizing,
                      clip, and the `contentVisible` flag ModuleLoader reads.
                      A module sets `contentWidth` and its content; it must
                      not bind implicitWidth itself. Workspaces.qml and
                      Privacy.qml deliberately don't use it — see below
shared/StyledText.qml every piece of text in the shell. Owns
                      renderType/font.family/default pixelSize so none of
                      those is a rule anyone has to remember. Colour is NOT
                      unified (three palettes) — state it at each site
shared/Icon.qml       StyledText sized off Theme.iconSize with a `sizeRatio`
                      per-glyph bias. Sets no anchors on purpose
shared/popup/         everything to do with anchored hover popups:
  HoverPopup.qml         base type for a hover-triggered popup (grace-period
                         close, PopupCoordinator registration) — Clock's
                         calendar and Weather's forecast are built on this
  Tooltip.qml            reusable hover tooltip; declarative `show` gated by
                         a `showDelay` dwell (500ms), no close grace period
                         (see its header comment for why it's not built on
                         HoverPopup.qml despite sharing AnchoredPopupWindow)
  AnchoredPopupWindow.qml base PopupWindow type owning just the
                         anchor-below-module positioning math, shared by
                         HoverPopup.qml and Tooltip.qml
  HoverPopupArea.qml     hover MouseArea that opens a LazyLoader-backed
                         HoverPopup after a `showDelay` dwell (500ms);
                         shared by Clock.qml/Weather.qml/Workspaces.qml.
                         `popupEnabled: false` skips the open entirely;
                         `cancel()` drops a pending/open popup on a click
  WorkspacePreviewPopup.qml HoverPopup showing a live scaled-down mock-up
                         of one Hyprland workspace, one ScreencopyView per
                         window at its real position — see the dated
                         section below for what makes this work
  PopupCoordinator.qml   pragma-Singleton — only one hover popup open at a
                         time process-wide
shared/osd/OsdWindow.qml the on-screen display: one shared bottom-centre
                      pill for volume/backlight/lock keys, driven by the `osd`
                      IPC handler in shell.qml. Replaces swayosd — see the
                      dated section below
shared/notifications/ the notification daemon's UI — see the dated section
                      below for why this is a separate subsystem from
                      shared/popup/ rather than built on it
  NotificationTheme.qml  pragma-Singleton palette/metrics matching the
                         swaync setup this replaces — deliberately not
                         shared/Theme.qml, see below
  NotificationCard.qml   one notification's visual; reused by both the
                         popup stack and the control-center list
  NotificationPopupWindow.qml top-right floating toast stack (PanelWindow,
                         not the module-anchored popup/ machinery)
  NotificationCenterPanel.qml click-triggered control-center panel
                         (PanelWindow), pinned open via
                         NotificationService.centerOpen
shared/ModuleGroup.qml the left/right pill-shaped module group (flush
                      against a screen edge, rounded only on the
                      center-facing side); used twice from Bar.qml with
                      edge: Qt.LeftEdge/Qt.RightEdge
shared/ModuleLoader.qml Repeater delegate for one named module: resolves a
                      module name to a Component and applies the
                      `contentVisible` Loader-visibility workaround
shared/WeatherIcons.js glyph/description lookup table for weather codes
shared/animations/WidthSpring.qml   Theme.springSpring/springDamping as a
                      one-line `Behavior on implicitWidth { WidthSpring {} }`
                      — Behavior/SpringAnimation-based, unused after the
                      FrameSpring rollout below but kept as a fallback
shared/animations/WorkspaceSpring.qml same, but Theme.workspaceSpring*
                      — the SpringAnimation-based Workspaces.qml variant,
                      also unused now, also kept as a fallback
shared/animations/FrameSpring.qml   FrameAnimation-driven spring (real
                      per-frame timing, not Behavior/SpringAnimation's
                      ~60Hz-capped QUnifiedTimer clock — see "capped near
                      60Hz" below) — every module's width-change easing
                      now uses this instead of WidthSpring.qml
shared/animations/WorkspaceFrameSpring.qml same, but Theme.frameSpringWorkspace*
                      — Workspaces.qml's own faster FrameSpring variant,
                      kept separate for the same reason WorkspaceSpring.qml
                      was
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
them.

Current layout: every output gets `mpd`, `submap`, `workspaces`,
`backlight`, `battery`, `volume`, `notifications`, `clock`; only `DP-1` (in
`mainScreens`) additionally gets `tray`, `privacy`, `weather`.

**Left/right group edge-spacing tuning is order-sensitive.** `leftGroup`'s
comment about the first module's glyph bearing covering
`moduleOuterMargin`, and `rightGroup`'s comment about needing it explicitly,
both assume the *default* left order (`mpd`, `submap`) and right order
(`clock` last). Reordering a screen's layout so a different module lands at
the flush screen edge may need re-tuning those margins for that edge.

## Comments and docs

Keep **code comments** short and concise. A comment earns its place by saying
*why*, not by restating what the line already says — one to four lines, no
prose blocks above every property, no retelling of the debugging session that
produced it. Delete a comment that's gone stale rather than growing it.

**Don't explain code by comparing it to swaync, waybar, or whatever else this
replaced.** A reader of the code has no access to those configs, and the
comparison dates fast. State the behavior or the intent — "the panel lists
these already, so the toast would be redundant", not "swaync hides its toasts".
Provenance for a measured constant belongs in this file, not at the call site.

**This file is the exception**: it's written for agents, so the long-form
explanation belongs here — measurements, rejected alternatives, the reasoning
behind a non-obvious choice. A code comment states the rule and, where the
reasoning is long, points at the section here that carries it.

## Style notes

- **Bar has real extra height below the content, not an overlay.** The
  bottom border is genuine added height, not painted over the content — see
  `implicitHeight: theme.barHeight + theme.barBorderHeight` in `Bar.qml`.

- **`.modules-left`/`.modules-right` are flush half-stadium shapes**, not
  floating capsules — rounded only on the side facing center. Needs Qt
  6.7+'s per-corner `Rectangle` radius properties, not a single `radius`.

- **Workspace color has three states.** Default = teal (`workspaceBg`),
  urgent = pink, active/focused = accent, empty = cream. A populated
  non-focused workspace must stay teal, not default to cream.

- **Quickshell's Hyprland `active` ≠ the single system-wide focus.**
  Quickshell `active` = focused per-monitor (can be true on N monitors at
  once); `focused` = the one true system-wide focused workspace. Use
  `modelData.focused` for the single accent highlight.

- **`HyprlandWorkspace` has no `windows`/`empty` property.** Read
  `modelData.lastIpcObject.windows` instead.

- **`.modules-center`'s pill caps are cream, fixed 15px on the container**,
  not a margin around the buttons — see `Workspaces.qml`'s `capWidth`.

- **Use `shared/StyledText.qml` / `shared/Icon.qml`, never a bare `Text {}`.**
  The default SDF renderer shows visible chromatic fringing on this machine,
  so every text item needs `renderType: Text.NativeRendering`. That used to be
  a rule spelled out here and repeated at ~65 call sites; it now lives in those
  two types instead. A bare `Text {}` in this repo is a bug. (Quickshell
  documents a global `//@ pragma NativeTextRendering` as of 0.3.1, which would
  cover the render type alone — the family, size, weight axis and hinting
  preference still need the shared type, so it isn't used.)

- **Anything clickable that's a glyph or a text label is a
  `shared/PressableIcon.qml`, never a `StyledText` + `MouseArea` pair.** It
  owns the shared feel: press-shrink (`PressSpring`), `Theme.accent` on
  hover (blue-green, same as a notification card's close button), pointer
  cursor, and the `interactive` gate that suppresses all three. A site sets
  `text`/`color`/`font.pixelSize` as on any `StyledText` and reacts to
  `onActivated`; `hitPadding` widens the hit area for tiny glyphs (the
  calendar's `‹`/`›`). The hover colour is laid over the site's own `color`
  binding with a `Binding { when: … }`, so a toggle that binds `color` to
  its state (MPRIS shuffle/loop) keeps working. Sites: the MPRIS transport
  row, the control-center header, the group card's button, the weather
  refresh, the calendar's month arrows and title. The notification ✕ chips
  are `CloseButton`, not `PressableIcon` (they have a filled circle), but
  follow the same rule by default: accent fill on hover, glyph goes black
  for contrast. A hand-rolled click target misses the hover colour
  silently — that's how the calendar header fell out of line.

- **`font.family` can't take a CSS-style comma fallback string.** QML only
  accepts one family; Qt fuzzy-resolves a joined string down to just the
  icon font, leaving Latin text falling back to some other, narrower font.
  Fix in use: `Theme.fontFamily` = `"Inter Variable"` alone, relying on
  Qt's automatic per-glyph fallback for Nerd Font icon codepoints
  (`font.families`, the correct fix, isn't registered on this Qt build's
  Text type — retry if that ever changes). Set in `StyledText.qml`, so no
  call site repeats it.

- **Weight is `StyledText`'s `bold`/`wght`, never `font.bold`, `font.weight`
  or `font.styleName`.** fontconfig exposes InterVariable.ttf as nine named
  instances (wght 100..900 in hundreds) and Qt matches against those, so
  by-number requests land on a face nobody designed — `font.weight: 450` and
  `font.weight: 500` render pixel-identical to Regular, and `font.bold` never
  reaches the Bold instance at all (Qt synthesises it off the 400 outline).
  `StyledText` sets `font.variableAxes` instead, defaulting to wght 450, and
  that axis silently overrides both `font.bold` and `font.styleName` at a call
  site. Measurements and the FreeType-level alternative that was rejected:
  the 2026-09-12 section at the end.

- **A `MultiEffect` source item holds a background plate, never the content.**
  A source item is rendered into a layer texture and that texture is drawn
  with linear filtering, so as soon as it lands on a fraction of a device
  pixel — routine at fractional scale, and unavoidable while it is being
  animated — everything inside it is resampled. Ordinary text is immune (Qt
  rounds glyph positions, even under an off-grid ancestor); text inside a
  layer is not. `NotificationCard.qml` had this right by accident and the
  control center had it wrong: it fed `source: panel` with the whole panel,
  which is what made it read blurry on the 1.25 output. Both now layer an
  empty `Rectangle` and keep the content as a sibling drawn after the effect.
  Measurements: the 2026-09-12 section at the end.

- **Offsets that place a bordered surface go through `Screens.snap()`.** A 1px
  border off the device pixel grid draws as two half-lit columns instead of
  one solid one, and at scale 1.25 a logical coordinate only lands on a whole
  device pixel when it is a multiple of 4 (3 at 1.333, 5 at 1.6 — no constant
  covers every output, hence a per-scale helper). `Screens.scaleFor()` reads
  the real scale from Hyprland: `ShellScreen.devicePixelRatio` is the integer
  `wl_output` scale, 2 on a 1.25 output, and Qt exposes the fractional one
  nowhere. This is polish for borders only — it is not what fixes text.
  `scaleFor()` is compositor-specific, but adds no portability debt:
  `shared/Screens.qml` was already the Hyprland seam (`focused()` reads
  `Hyprland.focusedMonitor`, and the import is file-scope), so a port to Niri
  rewrites two functions in one file instead of one. Verified to degrade
  rather than break: `Hyprland.monitorFor()` returns null for a screen it does
  not know — no throw — so `scaleFor()` gives 1, `snap()` becomes the identity
  on whole numbers, and the layout is exactly what this repo shipped before.

- **`StyledText` asks for `Font.PreferVerticalHinting`; don't "upgrade" it to
  full.** Qt Quick's native text path loads glyphs *unhinted* unless an item
  states a preference — fontconfig's system-wide `hintslight` reaches waybar
  and GTK, never a `QQuickText` — so without this the bar was the one surface
  on the desktop rendering unhinted. `PreferFullHinting` is measurably crisper
  and was tried on the live bar for exactly that reason; it mangles Inter at
  12px and was reverted the same day. Both measurements and the artifact list
  are in the 2026-09-12 section at the end. Any `FontMetrics` measuring the
  same face needs the same preference, or its advances don't match what gets
  drawn (`Workspaces.qml`).

- **`Workspaces.qml`'s button width needs a GTK-chrome allowance.**
  Formula: `Math.round(Math.max(label.implicitWidth + 18, 34))`, tuned
  empirically for a comfortable button size.

- **`.modules-left`/`.modules-right`'s 12px border is one-sided**, only on
  the inner/center-facing edge. Anchor the inner RowLayout to the flush
  edge, not `centerIn`, or the flush edge gets a spurious extra 12px too.

- **Screen edges aren't symmetric by construction.** Every module has both
  6px padding and 4px margin on each side — easy to model only the padding
  half. This only shows up on the two modules flush against the true screen
  edge (`Mpd` left, `Clock` right) — elsewhere `RowLayout` spacing hides it.
  Fixed via `theme.moduleOuterMargin` (4px), added only where a flush
  module actually needs it (`rightGroup` in `Bar.qml`; not `leftGroup`,
  since Mpd's own icon glyph bearing already covers it — adding it there
  would overshoot). **Lesson:** a spacing rule can have multiple additive
  parts; modeling only one can still look right almost everywhere by luck,
  and only fail at edge modules with no neighbor to hide behind.

- **A hover popup that should stay open when the cursor moves onto it
  needs a grace-period timer**, not a plain `anchorHover || popupHover` OR —
  the popup is a separate surface a few px away, so a plain OR closes it
  before the cursor arrives. `HoverPopup.qml` derives one `hovered` bool from
  the module's `anchorHovered` (written by `HoverPopupArea`) and its own
  surface `HoverHandler`, and a ~200ms `Timer` closes it only if `hovered`
  is still false when it fires. Both halves are `HoverHandler`s, not
  `hoverEnabled` MouseAreas: Qt keeps delivering hover to an accepting
  item's *ancestors* but stops at items *behind* it, so a hover MouseArea
  laid behind the content lost its hover — and closed the popup — the moment
  a `PressableIcon` sat inside the content.

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
  issue" instead of a real deadlock. This exact pattern shipped in an
  earlier `Privacy.qml` Loader (`visible: item ? item.visible : false`) —
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

- **`PopupAnchor.edges`/`.gravity` center on an axis when that axis's
  `Left`/`Right` flag is simply omitted** — not a separate "Center" flag,
  which doesn't exist (`Edges` is only `None|Top|Left|Right|Bottom`).
  Confirmed by reading Quickshell 0.3.0's `popupanchor.cpp`
  (`PopupPositioner::reposition`): with neither flag set, `anchorX` falls
  through to `anchorRectGeometry.center().x()` and the gravity side falls
  through to `anchorX - windowGeometry.width() / 2`. That width read is
  live — `windowGeometry` is the popup's *actual current* size at
  reposition time, and `ProxyPopupWindow` connects the popup window's own
  `widthChanged` straight to `reposition()` — so centering computed this
  way tracks the popup resizing after it's shown (e.g. `Tooltip.qml`'s text
  changing) for free. A hand-rolled `anchor.rect.x = center - popup.width /
  2` inside `onAnchoring` would look identical at first paint but go stale
  on any later resize, since `onAnchoring` only re-fires on rect/edge/
  gravity/window changes, not on the popup's own width. Used in
  `AnchoredPopupWindow.qml` to horizontally center `Tooltip.qml`/
  `HoverPopup.qml` under their anchor module instead of left-aligning.

## Visual polish beyond the base design

- Every module eases `implicitWidth` (`Theme.qml`'s `resizeDuration`) on
  content-size changes, which reflows the whole bar smoothly for free.
- `Workspaces.qml`'s focus highlight is a single shared `selection`
  Rectangle that slides/resizes between delegates, with labels kept as a
  separate static top layer so only the square moves.
- Hovering a workspace pill shows a live preview of that workspace
  (`shared/popup/WorkspacePreviewPopup.qml`); clicking closes it.

## Known limitations

- **`Privacy.qml`** shows a mic icon and a screen-share icon, both computed
  inline (no dedicated service — see the correction below).
- **`Mpd.qml`** polls `mpc` on a timer since mpd isn't exposed over MPRIS
  here and Quickshell has no built-in mpd client.
- **`Weather.qml`** natively implements the bar icon+temperature and a
  popup with current/hourly/daily forecast.
- **`Tray.qml`'s icon order isn't stable** — nothing sorts tray icons
  without an explicit `order` config, so it's just registration order and
  varies per restart. Not a bug to chase.
- **`Battery.qml`** reads `Quickshell.Services.UPower` inline (no service —
  same reasoning as `Privacy.qml`), and shows a `Tooltip` with upower's
  time-to-empty/full estimate. See the port note below.

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
that's actually just outside the capture (the window is 1px taller than
`barHeight + barBorderHeight` due to `margins.bottom: 1`).

**Working method:** capture the same geometry, diff the aggregate
group-edge position first, then crop matching sub-regions to compare
individual icons at zoom. For gap measurement within a crop, a
brightness-threshold column scan (cluster non-background columns into
per-glyph segments) beats raw pixel diffing, since antialiasing produces
false positives pixel-by-pixel.

## Correction: screen-share detection doesn't need `pw-dump` polling (2026-09-02)

Previous claim (now removed from Known limitations above) was that
Quickshell's `Pipewire` service could never see a screen-share stream:
`PwNode.type` really doesn't classify `Stream/Input/Video` (that part's
still true — `type` stays `Untracked`/`0` for it), but the conclusion drawn
from that — that `properties`/`ready` therefore *never* populate for such a
node — was wrong. The original test only tried a synthetic node with no
`PwObjectTracker` anywhere in the process; **an untracked Pipewire node
never gets its properties bound, full stop, regardless of media class** —
that's the actual rule, and it was misdiagnosed as being about video
streams specifically.

Reconfirmed empirically against a real capture (Firefox sharing a browser
tab via the portal, not a synthetic `gst-launch-1.0` node): a standalone
probe script (`qs -p`) with `PwObjectTracker { objects: Pipewire.nodes.values }`
showed the node's `properties["media.class"]` and `ready` populate and
update live. The same probe with no tracker at all reproduced the original
`ready: false, properties: {}` stuck state on the same live node — so the
fix genuinely is just "track the node", not "impossible via Quickshell".

Found by reading DankMaterialShell's `PrivacyService.qml`
(`AvengeMedia/DankMaterialShell`), which does exactly this — reads
`node.properties["media.class"]` off `Pipewire.nodes.values` directly, no
subprocess. Its `PwObjectTracker` filters to `objects.filter(node =>
!node.isStream)`, which looks like it should exclude a video *stream*
node — but `isStream` turned out to be false for this class of node too
(Quickshell only sets it for media classes it classifies into a real
`PwNodeType`, same root cause as `type` staying `Untracked`), so DMS's
filter includes it anyway. Not obviously robust reasoning to copy blindly,
so this repo just tracks every node instead of relying on that
coincidence.

**Fix:** `services/ScreenShareService.qml` (the `pw-dump`-polling
singleton) is deleted. Screen-share detection now lives inline in
`Privacy.qml` as `screenShareActive`, same shape as the pre-existing
`micActive` — a `PwObjectTracker` over `Pipewire.nodes.values` plus a scan
for `media.class === "Stream/Input/Video"`. (That scan is superseded as of
2026-09-08: the class alone also matches a webcam — see the Privacy.qml
section at the end.) No dedicated service: this
isn't owned subprocess/network I/O (the thing `services/*.qml` exists for
per the Layout section above), just a reactive read of a singleton
Quickshell already keeps process-wide. It also means the tracker only runs
on screens whose layout actually lists `privacy` (DP-1 only, currently) —
same cost-avoidance property every other DP-1-only module gets, which the
old always-on singleton didn't have.

**Lesson:** an empirical "confirmed" finding can still encode the wrong
mechanism. The synthetic repro *did* fail, but the write-up attributed the
failure to the wrong variable (media class) instead of the one that
actually mattered (tracked vs. untracked) because the untracked case was
never isolated as its own test. When retiring a workaround based on an old
finding, re-run the original repro's failure case alongside the fix, not
just the fix in isolation — that's what surfaced the real variable here.

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
lesson elsewhere in this file about not blindly copying DMS's reasoning):
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
see above) made no difference, ruling out AA-shader coverage as the cause —
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

## Spring/Behavior animations are capped near 60Hz regardless of the output's real refresh rate (2026-09-03)

User-reported: the control-center panel's slide-in spring looks stuttery.
`DP-1` (where the panel opens by default) runs at a genuine `239.99Hz` mode
per `hyprctl monitors -j` (not a VRR/fallback artifact — `vrr: false`,
`refreshRate: 239.99001`, focused, confirmed active). `DP-2` is 144Hz,
`HDMI-A-1` ~60Hz — three outputs, three different rates, all driven by one
Quickshell process.

**Root cause found empirically, not assumed:** relaunched `qs -p ./` with
`QSG_RENDER_TIMING=1` and toggled the panel via `qs ipc -p ./ call
notifications open/close` several times. The notification panel's
`QQuickWindow` (identified as the highest-frame-count window in the log
during the toggles) showed `polishAndSync`/`syncAndRender` firing at a
rock-steady ~15-16ms cadence throughout the entire spring animation —
i.e. ~60 updates/sec — never anywhere near the ~4ms a 240Hz output would
allow. Actual render/swap times in the log were 0ms, so the GPU/compositor
isn't the bottleneck; the animation driver simply never asks for more than
~60 redraws/sec.

Tested the obvious lever — `QSG_FIXED_ANIMATION_STEP=0` (found via `strings`
on `libQt6Quick.so.6`; the Qt Quick knob for whether the animation system
uses a fixed simulated timestep vs. real elapsed wall-clock time per tick)
— **zero effect**: identical ~15-16ms distribution with and without it, so
that env var controls the *delta* used per tick, not the *tick rate*
itself. `QUnifiedTimer`'s underlying GUI-thread timer interval that
actually paces those ticks is an internal Qt default (no env var, no QML
property) — not something fixable from this shell's code or launch
environment.

**Conclusion:** this is an upstream Qt Quick limitation affecting every
`Behavior`/`SpringAnimation`/`NumberAnimation` in this shell equally (not
specific to the notification panel), not a bug introduced by this repo's
code. It only becomes visually obvious on `DP-1` because 240Hz makes 60Hz
motion look chunky by contrast — the same spring on the 60Hz `HDMI-A-1`
output wouldn't show it. **No shell-side fix exists** (would require
patching Qt or shipping a custom C++ `QAnimationDriver`, out of scope for
a QML-only shell). The only lever actually available from QML is tuning
spring feel (duration/overshoot) so fewer discrete 16ms steps are visible
before it settles — not restoring true 240Hz motion.

**Process note:** diagnosing this required killing and relaunching the
live `qs -p ./` instance twice (once per env-var combination tested) —
each time via `qs ipc -p ./ call notifications open/close` in a loop to
generate animation frames, then reading `/tmp/qs-render-timing*.log` for
the busiest window's `polishAndSync` deltas. Restored the plain
(non-instrumented) instance afterward.

**Shell gotcha hit while diagnosing this: `pkill -f 'qs -p'` can kill its
own invoking shell.** `pkill -f` matches the full command line text of
every process, including the shell currently running the `pkill` command
itself — and that shell's own argv literally contains the substring
`qs -p` (it's part of the very command being run). Several kill attempts
during this session silently died with exit 144 and zero output because
of exactly this self-match. Fixed by using an exact-name match instead
(`pkill -x qs` / `pgrep -x qs`, matching just the process's `comm` name)
rather than a substring `-f` pattern that can appear inside the invoking
shell's own command line.

## Correction: a real fix for the 60Hz cap exists — FrameSpring, via FrameAnimation (2026-09-03)

The section above concluded "no shell-side fix exists" for
Behavior/SpringAnimation's ~60Hz cap. That conclusion was wrong — it
was true only for *that specific mechanism* (Behavior/SpringAnimation
riding `QUnifiedTimer`), not for QML animation in general.

Found by asking how DankMaterialShell (`/tmp/DankMaterialShell`, already
used elsewhere in this file as an API-reference comparison) handles the
same problem: it doesn't use `Behavior`/`SpringAnimation` for its spring
motion at all. `Common/SpringMotion.qml` hand-rolls the mass-spring-damper
ODE itself (`advance(dt)`, semi-implicit Euler, integrated in small
`1/240`s sub-steps for numerical accuracy) and drives it with
`QtQuick.FrameAnimation` (confirmed present in this machine's Qt build —
`QQuickFrameAnimation`, `QtQuick/FrameAnimation 6.4`, in
`/usr/lib64/qt6/qml/QtQuick/plugins.qmltypes`; this machine runs Qt
6.11.1). `FrameAnimation.onTriggered` fires once per *actual rendered
frame* of its window — tied to real vsync/frame-swap timing, reporting the
true elapsed `frameTime` — rather than `QUnifiedTimer`'s fixed ~60Hz
GUI-thread ticker. It isn't declarative like `Behavior`: there's no
"animate whenever this expression changes" wiring, so the consumer binds
to `.value` and calls `.retarget(newValue)` imperatively whenever the
desired target changes.

**Implemented as `shared/animations/FrameSpring.qml`**, a trimmed port of
DankMaterialShell's `SpringMotion.qml` (dropped `reducedMotion`/`enabled`/
`settleDurationMs`, not needed here). Stiffness/damping/mass default to
Hyprland's own spring config (`Theme.frameSpringStiffness/Damping/Mass` =
460/35/0.6) rather than `Theme.springSpring/springDamping` — those tune
Qt's `SpringAnimation` formula specifically and (per this file's existing
note on that section) do NOT share Hyprland's unit convention despite the
same underlying ODE shape; FrameSpring implements that ODE directly, so
Hyprland's actual physical constants are the correct values here, for the
first time.

**Rolled out everywhere `WidthSpring`/`WorkspaceSpring` (Behavior/
SpringAnimation) previously eased a module's `implicitWidth`**: Submap,
Backlight, Clock, Tray, Volume, NotificationCenter, Mpd, Weather,
Privacy's `PrivacyIcon`, and Workspaces.qml's whole spring set (pill
width, delegate width, selection indicator x/width) — plus the
notification control-center panel's slide (the animation that started
this whole investigation).

The four-step conversion ritual this section originally described (bind
`.value`, snap in `Component.onCompleted`, retarget from an `onXChanged`
handler) is **gone** — see the `to` section below; two of its four steps
failed silently when forgotten, which is exactly the kind of thing that
should not be documented prose. `WidthSpring.qml`/`WorkspaceSpring.qml`
(the old Behavior/SpringAnimation-based types) are left in place, unused
after this rollout — not deleted, since they're a legitimate fallback if
FrameAnimation ever turns out to have its own problem on some other
Quickshell/Qt combination.

## Workspaces.qml's FrameSpring conversion needed two more fixes beyond the swap itself (2026-09-03)

Converting Workspaces.qml's five coupled springs (pill width, each
delegate's width, and the selection indicator's `x`/width) to FrameSpring
using the same pattern as every other module's single, independent spring
made the sliding selection indicator visibly **wobbly** — but, critically,
**only on DP-1 (240Hz)**, not on DP-2 (144Hz) or HDMI-A-1 (60Hz). Two
distinct bugs, found and fixed in sequence; the first fix alone wasn't
enough, and a plausible-looking third "fix" (more damping) actively made
things worse and had to be reverted.

**Bug 1: independent per-spring `FrameAnimation` instances don't share a
clock, and Workspaces.qml's springs are tightly coupled.** Each
`FrameSpring` (as first written) owned its own private `FrameAnimation`,
measuring its own elapsed time independently. Confirmed via a temporary
per-frame `console.warn` of `value`/`target`/`velocity`: three separate
Workspaces.qml instances (one bar per screen, all rendering the same
global `Hyprland.workspaces` model) chasing the identical target reported
values differing in the 2nd decimal place at the "same" moment — small in
absolute terms, but real, measured timing skew between independently-clocked
instances. Old Behavior/SpringAnimation never had this problem: every
instance shared Qt's one `QUnifiedTimer`, so all of them always advanced
by the *exact* same `dt` per tick, keeping the pill, each delegate, and
the selection square (cosmetically overlaid pixel-for-pixel on its focused
delegate) perfectly locked together. **Fix:** a shared driver — originally a
`standalone: false` switch on `FrameSpring.qml` plus a hand-rolled
`sharedSpringDriver: FrameAnimation` in Workspaces.qml, since superseded by
`SpringGroup.qml` (see the 2026-09-06 section below). Either way the point is
the same: one `FrameAnimation` calls `advance(frameTime)` on all of this
file's springs in one `onTriggered` block, so they all move by the identical
real `frameTime` every tick. This measurably
reduced but did not fully eliminate the wobble.

**Bug 2: sub-pixel float values feeding non-antialiased edges.**
`wsDelegate` and `selection` both have `antialiasing: false` (existing,
deliberate — flush square buttons, avoids a 1px seam per this file's own
earlier note on `Workspaces.qml`). Feeding a *continuously-varying,
unrounded* spring float into `Layout.preferredWidth`/`width`/`x` on a
non-antialiased edge means each real frame's width/position can round to
a *different* device pixel than the previous frame, even though the
underlying value is moving smoothly — a rounding shimmer, not true motion
jitter. This bug already existed under the old Behavior/SpringAnimation
system too (same unrounded float, same non-antialiased edges) — but at a
~60Hz-capped sample rate there were only ever a quarter as many chances
per second for consecutive frames to round to different pixels, blurring
it into the motion; FrameSpring's genuine 240Hz sampling on DP-1 hits that
rounding boundary far more often, making it visible. **Fix:** wrapped
every consumption of a Workspaces.qml spring's `.value` in `Math.round()`
— the pill's `implicitWidth`, each delegate's `Layout.preferredWidth`, and
`selection`'s `x`/`width`. Confirmed by the user this fixed it.

**Dead end, instructive:** before finding bug 2, tried pushing the
Workspaces-variant FrameSpring damping ratio from ζ≈1.05 (barely
overdamped) to ζ≈2 (firmly overdamped) on the theory that the wobble was
classic underdamped overshoot. The user reported this made it *worse*.
That result alone disproves the overshoot theory — more damping can only
ever *reduce* real spring oscillation, never worsen it, so whatever was
being observed wasn't that. (Separately reasoned through why: for this
discrete/stepped integration, increasing damping past a certain point
lengthens the slower of the system's two decay eigenvalues, i.e. makes the
settle *tail* linger longer rather than cutting motion short — plausibly
compounding whatever the real per-frame rounding artifact looked like,
rather than damping it out.) Reverted the damping change once bug 2's fix
resolved the actual complaint. **Lesson:** a fix that only makes sense if
your diagnosis is right is itself a test of that diagnosis — when it makes
the symptom worse, that's a real, informative result, not noise to
retry-with-different-numbers past. Don't keep tuning the same knob after
it's moved the symptom in the wrong direction; that's a sign the knob
isn't the mechanism, not that it needs a bigger turn.

## An always-running FrameAnimation costs ~8% CPU at idle (2026-09-06)

`qs` sat at a constant 7-8% of a core doing nothing. Cause: Workspaces.qml's
shared spring driver was declared `running: true` unconditionally, on the
reasoning (written in the comment at the time) that `advance()` on a settled
spring is a cheap early-return no-op.

**That reasoning is wrong, and the mistake is worth internalising: the
callback's cost is not the cost.** A running `FrameAnimation` is a running
`QAbstractAnimation`, so for as long as it lives Qt Quick requests an update,
runs polish+sync, re-renders the scene graph and swaps a buffer *every frame*,
whether or not a single pixel changed. Measured on eDP-1 at 90Hz: ~90 wayland
commits/s and ~240 GPU ioctls/s at idle, 48% of profile samples in
`QSGRenderThread`. With the driver gated: **zero** commits, 0.2% CPU. Anything
that ticks per frame must be gated on having something to do.

**Fix:** `shared/animations/SpringGroup.qml`. Springs join a group by declaring
`group: someGroup` (replacing the old `standalone: false`); they register
themselves with it on creation, so nothing outside a Repeater delegate needs to
reach in — which also retired the `property alias preferredWidthSpring` that
only existed for the old driver's `repeater.itemAt(i)` walk. The group owns the
one `FrameAnimation`, gated **declaratively**: `running: group.anyRunning`,
where `anyRunning` scans the registered springs' own `running` flags — the same
state `advance()` clears when a spring settles.

Why declarative rather than "start it when something retargets, stop it when
nothing is running" (which was the first version of this fix, and worked): that
version had two imperative touch points, and adding a sixth spring while
forgetting the stop-side collection would freeze animations mid-flight. Binding
to the springs' own state means there is exactly one source of truth and no way
to forget either half. This is also what DankMaterialShell does — every
`FrameAnimation` in that tree is gated on a `running`/`_pending` flag, none is
ever left on (`Common/SpringMotion.qml`,
`Modules/DankIsland/VectorSpringMotion.qml`,
`Modules/DankBar/DankBarHoverController.qml`). Our `FrameSpring` inherited that
gating correctly for standalone springs; only the shared driver dropped it.
(DMS's other answer to coupled springs, `VectorSpringMotion`, integrates several
scalars inside one spring object — clean for a fixed component set like its
island's geometry, but it hand-unrolls every component through every function,
so it doesn't fit Workspaces' per-delegate springs, whose count changes with the
workspace list.)

Two subtleties worth keeping, both about destruction. A spring destroyed
mid-animation (workspace closed while its pill is still easing) emits no
`runningChanged`, so `anyRunning` would never re-evaluate and the driver would
stay on forever. **And a destroyed QObject sitting in a JS array is not null** —
it's a stale wrapper that throws `TypeError: Property 'advance' of object
TypeError is not a function` on any property access. The first attempt here
tried to have the group prune "null" entries from inside its own `onTriggered`,
which therefore threw every frame instead of pruning anything. Both are solved
by `FrameSpring` unregistering itself in `Component.onDestruction`, so the
group's array only ever holds live springs. Don't try to detect a dead QObject
by truthiness.

**Method note:** quickshell hot-reloads on file change, so A/B testing is
edit-file → measure, same PID. But a config reload burns a few hundred ms
rebuilding the scene, so **wait ~6s after each edit before sampling** — an early
pass measured immediately after the write and produced a per-module CPU table
that was pure reload noise (the tell: results alternated hot/cold with loop
order). `strace -f -c` is the crispest idle check: ~90 `sendmsg`/s when
rendering every frame, none at all when truly idle.

## Battery module, ported from waybar (2026-09-05)

`modules/Battery.qml` replaces the waybar `battery` module (and its
`battery#bat2` sibling) from `~/.config/waybar/config.d/common.json` +
`style.css`. Notes worth keeping:

- **Backed by `Quickshell.Services.UPower`, not `/sys/class/power_supply`.**
  This is not just convenience: waybar's own detection requires a battery
  directory to have `capacity` or `charge_now` (`battery.cpp`'s
  `refreshBatteries`), and this machine's `qcom-battmgr-bat` has *neither* —
  only `energy_now`/`energy_full` — plus a `power_now` that reads negative
  while discharging, which waybar parses into a `uint32_t`. upowerd handles
  all of that, aggregates multiple packs into its `DisplayDevice`, and
  already smooths the rate for time-to-empty, which is the EMA waybar has to
  hand-roll (`smooth_power_`).
- **`UPowerDevice.percentage` is 0..1**, unlike upower's own D-Bus property
  (0..100). Multiply before rounding.
- **Don't name a module property `state`.** `state` is `QQuickItem`'s own
  string property driving QML's states/transitions system; declaring
  `readonly property int state` over it shadows a built-in. Named
  `deviceState` here.
- **The battery/plug glyphs are drawn upright** (MDI `battery-*` and
  `power-plug` are vertical, nub on top). waybar rotates them into the usual
  horizontal battery with Pango's `gravity='west'` — which is 90° *clockwise*
  (Pango's `WEST` = "glyphs rotated 90 degrees clockwise"), i.e. QML
  `rotation: 90`. waybar's config applies that to the level and plugged icons
  but *not* to the charging bolt, so the bolt stands upright there; that
  asymmetry is reproduced as-is behind `rotateIcon`.
- **A rotated `Text` needs a wrapper sized off `TextMetrics.tightBoundingRect`,
  not the swapped `implicitWidth`/`implicitHeight`.** `rotation` doesn't
  affect an item's implicit size, so the glyph needs a wrapper to reserve the
  space its rotated form occupies — but `implicitHeight` is the whole line box
  (ascent + descent), ~5px taller than these glyphs' ink at `iconFontSize`.
  Using it as the rotated width gave a label→icon gap of 10.6px against every
  other module's 8.1px, which read as a visibly loose module. The ink rect
  (`tightBoundingRect`) is vertically centered in the line box for this font,
  so rotating about the wrapper's center lands it centered horizontally with
  no further correction. Measured with the column-scan method above: 7.5px vs
  Backlight's 8.1px, and identical 23.8px gaps to the modules on either side.
- **The critical state deliberately departs from `style.css`.** waybar's
  `#battery.critical:not(.charging)` blinks the module's *background* red↔white
  (0.5s, alternating) with the text going black. Here the label and icon turn
  `Theme.critical`, the label goes bold, and the pair pulses its opacity
  1 → 0.6 over 1.2s each way: a solid block of color fights the pill-shaped
  groups the bar is built from, and the 0.5s cadence reads as a distraction
  rather than a warning. The 30%-warning threshold is still computed
  (`level`) but, as in `style.css`, draws nothing.
- **`Theme.critical` is lightened from style.css's `#f53c3c`.** That red was
  only ever a *background* in waybar; as text on `groupBg` it's 2.68:1.
  `#FF8A80` is 4.40:1 and still unmistakably red. Related: an opacity pulse
  fades toward the background, so its trough costs real contrast (1.6:1 at
  0.3) — hence the shallow 0.6 floor plus bold, rather than a deep fade.
- **Use `font.weight`, not `font.bold`, with `Theme.fontFamily`.** Inter is a
  variable font and Qt selects along its weight axis by number; `font.bold`
  didn't visibly change the label here. Bold is applied to the percentage
  only — the Nerd Font fallback has no bold face, so Qt would synthesize a
  smeared glyph.
- **waybar's status → format mapping**, for reference when comparing:
  `Charging` → bolt, `Plugged` (on the adapter, not charging — including this
  laptop's 80% charge-end threshold, which upower reports as `PendingCharge`)
  → plug glyph, everything else including `Full` → `{capacity}%` + level icon.
  Level icons are indexed `capacity / (100 / size)` clamped to the last entry
  (`ALabel::getIcon`): 0-19, 20-39, 40-59, 60-79, 80-100.
- **Don't trust `UPower.onBattery` on this machine (2026-09-10).** The daemon
  reports `OnBattery: false` while the battery is plainly discharging: its
  `line_power_qcom_battmgr_usb` device sits at `online: yes` even with
  nothing plugged in, while sysfs says `online: 0` for that same supply — the
  daemon disagreeing with the kernel, not the hardware. `plugged` was
  `!charging && !full && !UPower.onBattery`, so the module showed the plug
  glyph on battery power. It now reads the battery's own
  `UPowerDeviceState.PendingCharge` instead, which is what "on the adapter,
  not charging" already means here. Prefer the device state over the global
  for anything else too.

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

## Refactor pass against DankMaterialShell and Noctalia (2026-09-06)

Both projects were re-read side by side with this repo — DMS (`/tmp/DankMaterialShell`,
636 QML files) and Noctalia, which is now a **C++** shell (`/tmp/noctalia`, 684
headers / 577 .cpp, meson, no QML at all), so only its design is transferable,
never its code. Most of both is scope this bar deliberately doesn't have
(DMS's `SettingsData` alone is 3570 lines, plus a plugin system and a widget
registry; Noctalia ships a user-facing TOML config with a validation schema).
What follows is what was actually worth taking.

### sysfs backlight *does* emit inotify — the old note was wrong

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

**Lesson (a repeat of the `pw-dump` one earlier in this file):** an empirical
"confirmed" negative can encode the wrong mechanism. The original test really
did fail, but the write-up blamed sysfs-vs-inotify in general rather than
whatever actually went wrong in that one probe. A second implementation doing
the thing you wrote off as impossible is the cheapest possible signal to go
re-run the experiment.

### FrameSpring is declarative now: `to:`

`FrameSpring` grew an optional `to` property. Bind it and the spring snaps to
the initial value on creation and retargets on every change; `snapTo()`/
`retarget()` remain for the springs that genuinely have no single resting
expression (the toast stack's entry animation, the mpris card's
direction-dependent slide). `NaN` is the unset sentinel — 0 would force a
resting target of 0 on those imperative springs.

Why this and not just a style note: of the four steps the old ritual needed,
**two failed silently**. No `Component.onCompleted: snapTo(...)` and the module
animates in from width 0 on every reload; no `onTargetWidthChanged: retarget(...)`
and the width freezes at its startup value forever, with nothing logged either
way.

Verified before writing it that a base type's `Component.onCompleted` and a
call site's own both run (base first, no shadowing) — that's what lets the
imperative call sites keep their handlers while the base's is a no-op for them.

### `BarModule`, `StyledText`, `Icon`

Modelled on DMS's `Modules/Plugins/BasePill.qml` (every DMS bar widget is a
`BasePill { content: Component { … } }`) and its `StyledText`/`DankIcon`.

`BarModule` deliberately uses **plain inheritance, not** DMS's
`default property alias content: <inner>.data`. DMS needs the alias because
`BasePill` wraps content in a background + ripple + Loader; this bar has no
such chrome, and an alias here would silently reparent each module's
`MouseArea`/`Timer`/`PwObjectTracker` into a nested item and change what
`anchors.fill: parent` means.

Three modules don't use it, on purpose: **Workspaces.qml** rounds its spring
output and drives five coupled springs off one `SpringGroup`; **Privacy.qml**
springs its per-app icons rather than its own width; **Submap.qml** does use it
but overrides `padding` and `implicitHeight` and puts its accent pill in a
child Rectangle. A base type doesn't have to be universal.

### `pragma ComponentBehavior: Bound`, everywhere

DMS has it in 225 of its 636 files. It's the compiler-level guard for this
file's worst documented bug class — an unqualified `modelData` in a delegate
resolving to an ancestor's instead of the delegate's own, silently, with wrong
data and no warning. Every delegate in this repo already declared its required
properties, so the rollout was clean; `shell.qml`'s `Variants` delegate got an
`id: bar` so its model access is qualified too.

### `MprisService`

~90 lines of player-selection policy (`mprisPlayers`, `mprisIndex`,
`defaultMprisIndex()`, `prev`/`nextMprisPlayer()`, slide direction, the
`suppressPop` flag) lived inside `NotificationCenterPanel.qml`, which had this
repo's own services/views split backwards. Moved to `services/MprisService.qml`,
mirroring DMS's `Services/MprisController.qml` (though ours is much thinner —
a selection cursor over `Mpris.players`, not a media abstraction). The panel
went 718 → 642 lines.

### `scripts/lint.sh` — and why there's no formatter

`qmllint` can't resolve `qs.*` imports on its own (Quickshell synthesises that
module at runtime; there are no qmldir files on disk), so every cross-file type
came back unknown and drowned the real findings. `scripts/lint.sh` builds a
throwaway shim tree of qmldir files + symlinks describing the same layout,
points qmllint at it with `-I`, and deletes it after.

It found six real problems on its first runs: four unqualified accesses
(`ModuleGroup.qml`, `Workspaces.qml`, both of `Weather.qml`'s forecast
delegates), `Tray.qml` reading a delegate's `modelData` through an `Item`-typed
handle (fixed by tracking the `SystemTrayItem` separately from the delegate it
anchors to — two different things that were conflated), and
`NotificationService.qml` reading fields off an untyped `createObject()` result
(fixed with `as NotifWrapper`, which was already a named type). `ModuleLoader`
also picked up `(item as Item)?.implicitWidth`.

**Nothing is suppressed by category.** A first version of `.qmllint.ini`
demoted whole categories (`MissingProperty`, `MissingType`, …) to `info` to get
a green run — which meant a genuine missing property anywhere would have been
downgraded to chatter, *and* left 28 lines of noise on every run, so clean and
broken looked identical. Instead every category stays fatal and `scripts/lint.sh`
carries an explicit list of individual known-unfixable findings, each with its
reason (`--all` prints them). 21 are suppressed today: 19 are gaps in
Quickshell's own qmltypes — `PanelWindowInterface` is literally
`isCreatable: false` in `quickshell-window.qmltypes`, and `Margins`, `Edges`,
`PopupAnchor`, `PopupAdjustment`, `QProcess::ExitStatus` and the
`NotificationAction` list type aren't exported — and 2 are deliberate
duck-typing (`Loader.item` in ModuleLoader, `Repeater.itemAt()` in
NotificationPopupWindow), where the type-safe alternative would mean forcing
every placeable module onto one base class that Workspaces shouldn't be on.

Verified it still bites: injecting an unqualified `modelData` into a Weather
delegate and a typo'd `Theme.groupTxt` into Volume made it report exactly those
two and exit 1.

`.githooks/pre-commit` runs it. **Not** enabled automatically — turn it on with
`git config core.hooksPath .githooks`.

**No formatter is wired up, deliberately.** DMS uses `qmlfmt` (not packaged
here); Qt's own `qmlformat` disagrees with this repo's style badly enough to be
a regression — it explodes `Bar.qml`'s deliberate one-line
`Component { id: x; Y {} }` declarations into four-line blocks and re-indents
object literals. Everything else in the tree already matches `qmlformat`
output, so if it ever gains a way to leave those alone, revisit.

### Considered and not done

- **Dropping `MpdService` for `Quickshell.Services.Mpris`** (one fewer
  permanent `mpc idleloop` subprocess, ~109 lines). Left alone at the user's
  request; also note `mpd-mpris.service` is currently *inactive* on this
  machine, so it would need enabling first, and the bar module would then show
  any MPRIS player rather than MPD specifically.
- **Deleting `WidthSpring.qml`/`WorkspaceSpring.qml`.** Still unreferenced, but
  they're a deliberate documented fallback; not this pass's call to reverse.
- **DMS's `Ref.qml` / `addRef`/`removeRef` service refcounting.** Buys nothing
  here — Quickshell instantiates `pragma Singleton` lazily, so a service whose
  module isn't in any screen's layout never starts in the first place.
- **`//@ pragma Env` for Qt tunables.** DMS pins `QSG_RENDER_LOOP=threaded` and
  friends in its `shell.qml`. ~~Nothing here currently depends on an env var~~ —
  **outdated**: `shell.qml` now pins `QSG_USE_SIMPLE_ANIMATION_DRIVER=1` and
  `QSG_RHI_BACKEND=vulkan`, each with measurements in the dated sections below.
  The principle still stands though — neither was set speculatively.
  `//@ pragma AppId` *was* added.

## Privacy.qml: media-class classification, camera vs. screencast (2026-09-08)

Three fixes, each measured against a live graph on this machine (Firefox
sharing a tab via the portal, then a webcam, with Bluetooth buds connected).

**Mic and video both key off `media.class` now**, instead of the mic going
through `PwNodeType.AudioInStream` and the video through a string compare.
`PwNodeType` has no `VideoStream` member, so only one of the two could ever
use it. The case that proves the two forms equivalent is the headset: it
publishes a permanent `bluez_capture_internal` node of class
`Stream/Input/Audio/**Internal**`, which Quickshell types `Untracked` and
which an exact `=== "Stream/Input/Audio"` likewise skips. **Exact compare,
never a prefix** — a prefix match lights the mic icon whenever those buds
are connected, with nothing recording. Noctalia matches exactly too
(`std::ranges::contains` over `kAudioCaptureConsumerClasses`).

**`Stream/Input/Video` alone does not mean screen share** — this corrects
the 2026-09-02 section above, which had screen-share detection as that
media class, full stop. A webcam produces the same class. Measured, the two
are indistinguishable from the consumer side: both are named `firefox` with
no `application.name`, differing only in a Firefox-specific `media.name`
(`webrtc-consume-stream` vs `camera-stream`). So a webcam on a video call
was lighting the screen-share icon.

The discriminator is the producer. The portal publishes its own
`Video/Source` node (`xdg-desktop-portal-hyprland`) that exists only for
the life of a cast — verified by watching it appear and disappear, with a
fresh session id each time (`xdph-streaming-718498`, then `-140892`). The
camera device node (`libcamera_input…`, `media.role: Camera`) is permanent,
so its presence means nothing. `screencastPortalActive` now gates the
screen glyph.

Note the name heuristics DankMaterialShell (`looksLikeScreencast`) and
Noctalia (`kScreenShareNamePrefixes`) both use would fail here: they match
the *capture* node's name, which on this machine says nothing about
screens. Known limit of the portal gate: while a cast and a webcam run at
once, the camera consumer is counted as screen too. Separating them needs a
`PwNodeLinkTracker` per consumer, which this module's scope doesn't justify.

**One app, two names.** Firefox reports `application.name` "Firefox" on its
mic stream and *none at all* on its video one, whose `node.name` is a
lowercase "firefox". The merge key was the raw string, so one app rendered
as two rows — exactly the split that merge exists to prevent. Key is
case-folded now, and the app-reported name wins for display. Measured 2
rows → 1.

**`isStream` bit again.** The 2026-09-02 section already records that
`isStream` is false for a `Stream/Input/Video` node. This pass proposed
narrowing the tracker to `filter(n => n.isStream)` anyway — which would
have dropped the one node the module needs — and only caught it by
re-measuring. Re-read that section before touching the tracker.

### Probing Quickshell state without disturbing the running bar

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

## Workspace hover previews via per-window screencopy (2026-09-11)

`Workspaces.qml` pills open a `WorkspacePreviewPopup` on hover: a
monitor-aspect canvas (`Theme.workspacePreviewWidth` wide, 640px) with one
`Quickshell.Wayland.ScreencopyView` per window, placed from `hyprctl`'s
`at`/`size`. What was checked before building it, all on Hyprland 0.56.2 /
Quickshell 0.3.1:

- **There is no "capture a workspace" primitive.** Hyprland exposes
  output capture and per-window capture (`hyprland_toplevel_export_v1`,
  `ext_foreign_toplevel_image_capture_source_manager_v1`), nothing
  in between, so the preview composes windows itself. Output capture would
  only ever show the workspace currently on that monitor (plus the bar).
- **Windows on workspaces that aren't on any monitor still capture, and
  stay live.** The compositor re-renders the window offscreen for the
  capture and keeps feeding the client frames while a capture is running:
  a probe capturing a `foot` running `date` in a loop on an off-screen
  workspace showed the time line changing between two grabs 3s apart
  (`ScreencopyView { live: true }`). So no stale-snapshot caveat. The one
  thing that does go stale: a window *resized* while off-screen (e.g.
  tiled next to a new neighbour) keeps its old buffer until the client
  redraws, so its thumbnail is briefly stretched into the new slot.
- **Geometry is `HyprlandToplevel.lastIpcObject`, refreshed on open** with
  `Hyprland.refreshToplevels()` from the popup's `Component.onCompleted`
  (creation == open, since it's LazyLoader-built) — the same
  snapshot-goes-stale property that made Workspaces.qml count windows via
  `toplevels` instead of `lastIpcObject.windows`. `at`/`size` and monitor
  `x`/`y` are logical coordinates; `HyprlandMonitor.width`/`height` are
  the physical mode size, so divide `scale` back out (and swap axes on odd
  `transform`s).
- **Paint order**: hyprctl lists windows in creation order, which says
  nothing about stacking, so the popup sorts tiled < floating <
  fullscreen, each by `focusHistoryID` descending (0 = most recent, drawn
  last).
- **Empty workspaces get no popup at all** (`HoverPopupArea.popupEnabled`),
  rather than a popup that's built, never becomes visible, and so never
  hits the `onVisibleChanged` teardown.
- **A click on a pill calls `HoverPopupArea.cancel()`** before activating
  the workspace, which closes via `HoverPopup.close()`. `close()` now also
  deactivates itself with `PopupCoordinator`: it's followed by LazyLoader
  teardown, and a coordinator still pointing at the destroyed popup would
  call `close()` on it at the next hover popup's `activate()`.
- **Cost**: views only exist inside the popup, one workspace at a time,
  destroyed on close. Buffers are dmabuf at the window's physical size
  (e.g. 2931x1786 for a full-height window at scale 1.6), never CPU
  copies; `constraintSize` didn't shrink them in a probe, so it's unused.

Verification notes:
- `hyprctl dispatch` on 0.56 takes Lua (`hl.dsp.focus({workspace = "s"})`,
  `hl.exec_cmd(cmd, {workspace = "f"})` — no `silent` rule, so exec
  switches to that workspace). `hl.dsp.window.close({address = ...})`
  **ignored the address and closed the active window** — which was the
  terminal running the session. Kill test windows by pid instead.
- Grabbing a popup screenshot right after the hover lands catches
  Hyprland's popup fade-in and looks see-through; wait a beat.

## The 60Hz animation cap is back (and was never really gone): Qt paces animations off the wrong screen (2026-09-12)

User-reported: the notification panel's open/close slide looks laggy on DP-1
(240Hz). It is not lazy loading — `NotificationCenterPanel` is instantiated
eagerly in `shell.qml`, the only `LazyLoader` near it is
`NotificationCenter.qml`'s tooltip — and it is not the spring maths either.
FrameSpring was doing exactly what it was written to do; it just cannot create
frames nobody asked for.

**Measured, in an isolated `qs -p` instance holding only the panel** (config in
a scratch dir symlinking `shared/`, `services/`, `modules/`, so the live shell
was never touched), with `QSG_RENDER_TIMING=1` sliced per phase by byte offset
into the log:

| phase | frames | interval |
|---|---|---|
| panel idle open | 0 | — (nothing renders when settled, as intended) |
| open slide | 38 | median 16ms |
| close slide | 36 | median 16ms |

`QSG_INFO=1` explains it in two lines:

```
Animation Driver: using vsync: 16.68 ms
Window ... is determined to have broken vsync throttling (3.285714 < 8.340144)
switching to system timer to drive gui thread animations to remedy this
```

16.68ms is **HDMI-A-1's** 59.95Hz. A `Screen.name` probe inside a
`PanelWindow` whose Quickshell `screen` is DP-1 prints `qtScreen=HDMI-A-1
qsScreen=DP-1`: **Quickshell's layer-shell windows never update
`QWindow::screen()`, so every one of them looks like it's on Qt's primary
screen.** Qt's `QSGAnimationDriver` takes its expected vsync interval from that
screen, then sees real frames arriving every 3.3ms on DP-1, concludes the
window's vsync throttling is broken (measured < expected/2) and switches **all
GUI-thread animations, process-wide**, to a ~60Hz system timer. That is the
16ms cadence above — and it is why the slide looked 60Hz-ish even though the
earlier `FrameSpring` rollout was supposed to have fixed this class of problem:
`FrameAnimation` is a GUI-thread animation, so it ticks once per *rendered*
frame, and the render loop had stopped asking for more than ~60 of those per
second. FrameSpring fixed the *pacing source* (it does integrate the true
elapsed `frameTime`); it never had any say over the *frame rate*.

**Fix: `//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1` in `shell.qml`.** The
simple driver has neither the refresh-rate guess nor the broken-vsync
heuristic. Measured after the change, same harness, same method:

| | frames per open+close | interval | `FrameAnimation.frameTime` | 1000ms `NumberAnimation` |
|---|---|---|---|---|
| before | 74 | median 15ms | 16.01ms (accurate, but 60/s) | 961ms wall |
| after | 532 | median 4ms | 4.17ms (accurate, 240/s) | 1003ms wall |

So it is not a trade: timed animations get *more* accurate (the system-timer
fallback ran them ~4% short), idle cost is unchanged — **0 frames and 0 CPU
ticks over 3s with the panel sitting open**, since the gating from the
always-running-FrameAnimation section above still holds — and one open+close
cycle costs 8-9 CPU ticks instead of 4, i.e. ~4x the frames for ~2x the CPU,
only while something is actually moving. Plain comment lines between `//@
pragma` lines parse fine (checked in the harness), so the reasoning lives next
to the pragma.

**This supersedes the conclusions of both earlier sections.** "No shell-side
fix exists" (the 2026-09-03 60Hz section) was wrong twice over: FrameSpring was
the first correction, this pragma is the second, and the two fix *different*
halves of the same symptom. Note also that the pragma only takes effect at
process start — a hot reload keeps the old driver, so A/B testing it needs a
full kill and relaunch (use the PID recorded at launch, or match `comm == qs`
plus the config path from `/proc`; `pkill -f 'qs -p'` still self-matches the
invoking shell, per the earlier note).

**No, this does not make `FrameSpring` redundant — measured 2026-09-12.** The
obvious follow-up question is whether the pragma lets us drop FrameSpring and go
back to `Behavior { SpringAnimation {} }`. It does not: the two fixes remove
*different* 60Hz caps. Same harness, one process per driver, a 500px travel on a
plain Rectangle's `x`, counting property updates:

| | default driver | with the pragma |
|---|---|---|
| `Behavior { SpringAnimation }` | 62 updates/s | **62 updates/s** |
| `Behavior { NumberAnimation { duration: 500 } }` | 63/s (480ms wall) | **241/s** (503ms wall) |
| `FrameSpring` | ~60 frames/s | **~240 frames/s** |

`NumberAnimation` tracks the driver, so every duration-based animation in the
shell (the DND toggle, the mpris slide's siblings) got faster and more accurate
for free. `SpringAnimation` does not move at all: ~62 updates/s with a driver
ticking at 240Hz, in the same process and run where `NumberAnimation` managed
241/s. That isolates the cap inside `QQuickSpringAnimation` itself — it
integrates on its own fixed timestep no matter how often it is ticked — which is
exactly what FrameSpring was written to escape. Dropping FrameSpring would put
every spring in the shell back at 60Hz while everything around it ran at 240Hz.

**Leftover, not fixed here:** the root cause is upstream — Quickshell not
setting the real `QScreen` on its layer-shell windows. With that fixed Qt would
compute 4.17ms, the heuristic would never trip, and the default driver would be
fine. Worth reporting upstream; the pragma is the local workaround.

**Method note:** `QSG_RENDER_TIMING` output goes to stdout through
quickshell's own message handler, which is **block-buffered when redirected to
a file**. Short measurement phases (2-3s) can end entirely inside the 4KB
buffer and read as "zero frames" — two full measurement rounds were thrown away
to this. Launch under `stdbuf -o0 -e0`, append to one log, and slice phases by
`stat -c %s` offsets; truncating the log mid-run does not work either (the
process keeps its old file offset). And per-frame instrumentation needs to know
what it is counting: a `console.warn` in `FrameSpring`'s `onValueChanged` fires
once per *integration sub-step* (4 per frame at 16ms, ~1-2 at 4ms), not once
per frame, which makes 60Hz look like 250Hz.

## Vulkan RHI backend: a third less memory, and it changes nothing else (2026-09-12)

User asked whether `QSG_RHI_BACKEND=vulkan` (which people recommend for
Quickshell online) is worth it, and specifically whether it would help the RSS
on this 3-screen machine. It does, and that is the *only* thing it changes.

**Memory, the reason to do it.** Synthetic harness, 6 layer-shell windows
across all 3 screens (a full-width bar plus a 400x300 popup per screen), RSS
sampled at t=7s, three reps per backend:

| backend | RSS |
|---|---|
| opengl | 258 / 256 / 257 MB |
| vulkan | 168 / 169 / 171 MB |

~88MB, ~34%. The cost is **per-window**, which is why it matters here: scaling
the same harness from 1 window to 6 cost OpenGL ~12.6MB/window and Vulkan
~3-8MB/window. The real shell (12 `Creating QRhi` windows) came up at **280MB
on Vulkan against 346MB on OpenGL** — directionally the same, but note that
346MB reading was a long-uptime process and 280MB was fresh, so the controlled
three-rep table above is the real evidence, not that pair.

CPU was slightly lower too (22-25 vs 28-29 ticks over 5s of continuous
animation), but that is close enough to noise to not claim.

**It does NOT replace `QSG_USE_SIMPLE_ANIMATION_DRIVER=1`.** The obvious hope
was that the Vulkan backend would report a sane vsync interval and stop the
broken-vsync heuristic from tripping. It does not — the heuristic fires
identically, because the root cause is Quickshell not setting the real
`QScreen` on layer-shell windows, which has nothing to do with the RHI backend:

```
opengl: broken vsync throttling (3.142857 < 8.340144)
vulkan: broken vsync throttling (4.000000 < 8.340144)
```

**It does NOT make `FrameSpring` redundant either.** Same harness as the
section above (500px travel, counting property updates/s on DP-1 @240Hz), now
crossed with the backend:

| | opengl | vulkan |
|---|---|---|
| `NumberAnimation`, default driver | 60/s | 60/s |
| `NumberAnimation`, simple driver | 240/s | 237/s |
| `SpringAnimation`, default driver | 60/s | 60/s |
| `SpringAnimation`, simple driver | **62/s** | **62/s** |

The spring cap is inside `QQuickSpringAnimation`'s own fixed timestep and the
backend cannot see it, let alone move it. Both existing fixes stay.

**`ScreencopyView` works on Vulkan** — this was the one real risk, since the
dmabuf import is backend-specific (the binary calls `eglCreateImage` for the GL
path and `QVulkanDeviceFunctions::vkCreateImage` for the Vulkan one, so
Quickshell 0.3.1 implements both). Verified with a live `captureSource:
Quickshell.screens[0]`: `hasContent=true` and a correct 1440x2560 `sourceSize`
on both backends. RADV advertises `VK_EXT_external_memory_dma_buf` and
`VK_EXT_image_drm_format_modifier`, which is what that path needs.

**Caveats.** `radv is not a conformant Vulkan implementation, testing use only`
is printed at every startup and is normal/harmless. Vulkan recreates the
swapchain on every window resize (`Creating recycled swapchain of 3 buffers`),
which OpenGL has no equivalent step for — worth remembering if the adaptively
sized notification popups ever look janky. Presentation mode is FIFO (vsync).
And the 3-image swapchain means a *very* large window would cost more on Vulkan
than GL's 2 buffers; nothing here is near that size.

This supersedes the "`//@ pragma Env` for Qt tunables / nothing here currently
depends on an env var" bullet under **Considered and not done** — `shell.qml`
now pins two.

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
overscan (`rightMargin: -2`, with `controlCenterMarginV: 50`) put its left
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
nothing here uses opacity — and the surface is now far larger than the pill it
paints, which the `blur` layerrule does not mind: Hyprland masks the blur by
the surface's alpha, the same way the full-screen control-centre surface gets
blur only under its plate.

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

## A machine with no battery blinked an invisible module at 3.2% CPU (2026-09-14)

`qs` sat at ~3.2% of a core with nothing on screen moving — the same *class* of
bug as the always-running-`FrameAnimation` section above, but with a completely
different cause and a much wider blast radius.

**Cause:** `Battery.qml`'s critical-level pulse. `criticalBlink` was
`level === "critical" && !charging`, and `level` is derived from `percent`,
which falls back to `0` when UPower has no real device:

```
readonly property int percent: device && device.ready ? ... : 0
readonly property string level: percent <= 15 ? "critical" : ...
```

On a machine with no battery at all (`upower -i .../DisplayDevice` →
`battery-missing-symbolic`, `percentage: 0%`, state `Unknown`) that chain reads
0% as *critical*, `charging` is false, and the `SequentialAnimation` with
`loops: Animation.Infinite` runs for the life of the process. `contentVisible`
is false at the same time, so the module draws nothing — **the shell was paying
full frame rate to animate the opacity of a hidden item.** This config is shared
between a laptop (`eDP-1`, a real battery) and a desktop (`DP-1`/`DP-2`/
`HDMI-A-1`, none), so it only ever showed up on one of them.

**Fix:** fold the readiness check into the gate —
`criticalBlink: contentVisible && level === "critical" && !charging`. One line.
The general rule: a fallback value chosen to keep bindings safe (`0` here) will
be *compared against thresholds* somewhere downstream, and 0 passes every
"is it low?" test. Gate the consumer on "is there real data", not just on the
derived level.

**A running animation is process-wide, not window-local.** This is the part
worth internalising beyond this bug. The earlier section measured one output;
this one measured three, and *all three bars re-rendered every frame* even
though `battery` is a module on the right-hand group only and was invisible.
Qt's render loop keeps every showing window updating for as long as any
`QAbstractAnimation` in the process is running. So a single stuck animation
anywhere costs the **sum** of every output's refresh rate — here 240 + 144 + 60
= 444 frames/s of pure waste.

**Measurement, without `strace`.** `kernel.yama.ptrace_scope = 1` blocks
attaching to an already-running `qs`, which rules out this repo's usual
`strace -f -c` check unless you relax it (`sudo sysctl -w
kernel.yama.ptrace_scope=0`, and put it back to `1` afterwards). The
privilege-free substitute is **per-thread voluntary context switches** out of
`/proc/<pid>/task/*/status`, sampled twice:

| render thread | wakeups/s | monitor | refresh |
|---|---|---|---|
| 264947 | 288.5 | DP-1 | 240 Hz |
| 264953 | 183.2 | DP-2 | 144 Hz |
| 264954 | 71.7 | HDMI-A-1 | 60 Hz |

A constant ~1.2 wakeups per vblank on every output is the signature of
"rendering every frame", and it needs no privileges at all. It is also a
*better* signal than `%CPU`: it says which windows are rendering and at what
rate, where `%CPU` only says "high". Once ptrace was relaxed, `strace -f -c`
agreed — 148,891 syscalls / 6s before (2,924 `sendmsg`, i.e. ~487 commits/s
against the 444 Hz total), **1 syscall / 6s after**.

**Bisecting by layout is fast and safe.** `shell.qml`'s `mainLayout` /
`defaultLayout` arrays are the natural bisection knob: empty both, reload, then
add modules back in halves. Emptying them took 32 ticks/10s → 4, which proved
it was a module and not one of the always-instantiated shared windows
(`NotificationPopupWindow`, `NotificationCenterPanel`, `OsdWindow`) in four
seconds of editing. Six reloads found `battery` alone at 29-30 ticks/10s with
every other module at 0. Honour the 6s settle from the method note above, and
note that `touch` does **not** trigger quickshell's reload — the file's
contents have to actually change.

Final numbers on the full shell: **32-36 ticks/10s → 1 tick/20s**, 0 render
wakeups/s on all three outputs.

### The pulse itself was the wrong shape, and "gentler" is not the fix

Follow-up from the user, and a fair one: a laptop that *does* reach 15% would
have blinked legitimately, burning power at exactly the moment it has none to
spare. The intuitive fix — make the pulse slower or shallower — does nothing.
Measured with the blink forced on and the module actually drawing:

| variant | idle cost |
|---|---|
| the pulse as written (1.2s legs, infinite) | 55 ticks/15s — 3.67% of a core |
| **the same pulse with 6s legs** | **56 ticks/15s — identical** |
| a Timer stepping opacity 1 → 0.6 every 1.2s | 6 ticks/15s — 0.4% |
| a bounded pulse, once it has finished | **0 ticks/15s** |

Row two is the one to remember. **The cost of an animation is binary, not
proportional to how fast it moves.** Any continuously-varying property renders
every frame for as long as it varies, so amplitude and period are free and
*duration* is the only thing you are actually buying. Extrapolated to a single
90Hz laptop panel this was ~0.7-0.8% of a core sustained, and the CPU number
understates it: the real cost is holding the GPU and the compositor's commit
path out of idle indefinitely.

**Chosen: a bounded pulse.** `loops: 3` (~7s) instead of `Animation.Infinite`,
re-fired on entering critical and on each further whole percent lost, with the
solid `Theme.critical` text carrying the warning in between. The designed look
is preserved exactly — it is the same fade, it just stops — and steady-state
cost is zero. The rejected alternatives are worth knowing: the Timer-stepped
toggle is ~9x cheaper than today but still costs forever *and* turns the
deliberate slow fade into a hard blink, which this module's own comment argues
against; dropping the motion entirely is free but throws away the signal.

Three implementation details, each of which is a trap:

- **`restart()` on a bound `running` breaks the binding.** The animation is
  driven entirely from handlers now (`onCriticalBlinkChanged`,
  `onPercentChanged`, `Component.onCompleted`); there is no `running:` line
  left. Keeping both would work exactly once.
- **Re-pulse on "a percent *lost*", never on "percent changed".** UPower's
  reading wobbles a point either way near the end, and firing on the way back
  up puts the animation back on more or less permanently — reintroducing the
  bug through the fix. `pulsedAt` is the low-water mark that prevents it.
- **`Component.onCompleted` is not redundant here.** A reload with the battery
  already critical evaluates the binding during creation, which can beat
  `onCriticalBlinkChanged` being connected.
