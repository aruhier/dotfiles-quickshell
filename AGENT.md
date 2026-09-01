# AGENT.md

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

```
shell.qml             Variants{ model: Quickshell.screens } → one Bar per
                      output; also owns the per-screen layout config (which
                      modules, which screens get which set)
modules/Bar.qml       PanelWindow per output; left/center/right groups,
                      rendered generically from the {left,center,right}
                      `layout` shell.qml hands it — no per-module or
                      per-screen special-casing lives here
modules/*.qml         one file per bar module — thin views, no owned
                      subprocesses/network/timers for cross-monitor state
services/*.qml        pragma-Singleton types holding state + the actual
                      subprocess/network I/O for anything system-wide
                      (BacklightService, MpdService, SwayNCService,
                      WeatherService) — one poll/subscription/fetch cycle
                      for the whole process regardless of monitor count
shared/Theme.qml      pragma-Singleton palette + metrics — shared
                      process-wide, not one instance per output
shared/popup/         everything to do with anchored hover popups:
  HoverPopup.qml         base type for a hover-triggered popup (grace-period
                         close, PopupCoordinator registration) — Clock's
                         calendar and Weather's forecast are built on this
  Tooltip.qml            reusable hover tooltip; declarative `show`, no
                         grace period (see its header comment for why it's
                         not built on HoverPopup.qml despite sharing
                         AnchoredPopupWindow)
  AnchoredPopupWindow.qml base PopupWindow type owning just the
                         anchor-below-module positioning math, shared by
                         HoverPopup.qml and Tooltip.qml
  HoverPopupArea.qml     hover MouseArea that opens a LazyLoader-backed
                         HoverPopup; shared by Clock.qml/Weather.qml
  PopupCoordinator.qml   pragma-Singleton — only one hover popup open at a
                         time process-wide
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
                      — every module's width-change easing
shared/animations/WorkspaceSpring.qml same, but Theme.workspaceSpring*
                      — Workspaces.qml's own faster spring, kept separate
                      so tuning it doesn't also speed up every other module
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
`backlight`, `volume`, `swaync`, `clock`; only `DP-1` (in `mainScreens`)
additionally gets `tray`, `privacy`, `weather`.

**Left/right group edge-spacing tuning is order-sensitive.** `leftGroup`'s
comment about the first module's glyph bearing covering
`moduleOuterMargin`, and `rightGroup`'s comment about needing it explicitly,
both assume the *default* left order (`mpd`, `submap`) and right order
(`clock` last). Reordering a screen's layout so a different module lands at
the flush screen edge may need re-tuning those margins for that edge.

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

- **Every `Text {}` needs `renderType: Text.NativeRendering`.** The default
  SDF renderer shows visible chromatic fringing on this machine; native
  rendering gives crisp text. No global setting exists for this — every
  `Text` needs it explicitly.

- **`font.family` can't take a CSS-style comma fallback string.** QML only
  accepts one family; Qt fuzzy-resolves a joined string down to just the
  icon font, leaving Latin text falling back to some other, narrower font.
  Fix in use: `Theme.fontFamily` = `"Inter Variable"` alone, relying on
  Qt's automatic per-glyph fallback for Nerd Font icon codepoints
  (`font.families`, the correct fix, isn't registered on this Qt build's
  Text type — retry if that ever changes).

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
for `media.class === "Stream/Input/Video"`. No dedicated service: this
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

## Inspiration for later: click-triggered popups (2026-09-02)

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

**If this bar ever grows a click-triggered popup** (e.g. a settings/context
menu, as opposed to a hover-preview), `PopupCoordinator`'s single
`activate`/`deactivate` pair won't be enough — it has no concept of
"pinned open regardless of cursor position." Worth revisiting this pinning
scheme then. Not implemented now — no click-triggered popup exists yet,
and AGENT.md's mandate is not to grow scope pre-emptively.
