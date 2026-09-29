# Style notes

## Rules

- **Bar has real extra height below the content, not an overlay.** The
  bottom border is genuine added height, not painted over the content — see
  `implicitHeight: Theme.barHeight + Theme.barBorderHeight` in `Bar.qml`.

- **`.modules-left`/`.modules-right` are flush half-stadium shapes**, not
  floating capsules — rounded only on the side facing center. Needs Qt
  6.7+'s per-corner `Rectangle` radius properties, not a single `radius`.
  A second group on the same edge (the cream submap group) keeps that
  shape and tucks under the previous group's cap rather than butting
  against it flat: a flat seam between two colours was tried first and
  read as one pill cut in two, while the overlapped cap keeps each group
  its own pill. The tucked group pads `capRadius + groupEdgePadding` on
  that side so its text sits 18px from the cap tip, same as the previous
  group's text on the other side of it. Both of a group's colours come
  from its layout entry (`color`, `textColor`); the modules inside read
  `textColor` rather than the theme's group text, so the entry is the one
  place a coloured group is defined.

- **Workspace colour follows state** (the list is in `Workspaces.qml`'s
  header): has windows = `workspaceBg` (teal), empty = `workspaceEmptyBg`
  (cream), urgent = `workspaceUrgent`, active on its monitor but not focused
  = `workspaceActiveBg`, focused = accent via the sliding `selection`. A
  populated non-focused workspace must stay teal, not default to cream.

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

- **Inside a popup or panel, anything clickable that's a glyph or a text
  label is a `shared/PressableIcon.qml`, never a `StyledText` + `MouseArea`
  pair.** Not on the bar itself: a bar module (Volume, Weather, the bell, a
  tray icon, a workspace pill) is clicked as a whole, through a module-wide
  `MouseArea` (or `HoverPopupArea`, a `MouseArea`) with a
  pointer cursor and no press or hover feedback — the bar keeps a still,
  flat look (decided 2026-09-28). It
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
  `notes/text.md`.

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
  Measurements: `notes/text.md`.

- **Offsets that place a bordered surface go through `Screens.snap()`.** A 1px
  border off the device pixel grid draws as two half-lit columns instead of
  one solid one, and at scale 1.25 a logical coordinate only lands on a whole
  device pixel when it is a multiple of 4 (3 at 1.333, 5 at 1.6 — no constant
  covers every output, hence a per-scale helper). `Screens.scaleFor()` reads
  the real scale from Hyprland: `ShellScreen.devicePixelRatio` is the integer
  `wl_output` scale, 2 on a 1.25 output, and Qt exposes the fractional one
  nowhere: none of `ShellScreen`'s fields yield 1.25 (its two pixel
  densities are Qt's DPI figures, with a ratio of 1.167). This is polish for borders only — it is not what fixes text.
  `scaleFor()` is compositor-specific, but adds no portability debt:
  `shared/Screens.qml` was already the Hyprland seam (`focused()` reads
  `Hyprland.focusedMonitor`, and the import is file-scope), so a port to Niri
  rewrites two functions in one file instead of one. Verified to degrade
  rather than break: `Hyprland.monitorFor()` returns null for a screen it does
  not know — no throw — so `scaleFor()` gives 1, `snap()` becomes the identity
  on whole numbers, and the layout is exactly what this repo shipped before.

- **A surface's own size goes through `Screens.snapSurface()`.** Snapping
  offsets inside a surface can't help when the surface itself is a fractional
  number of device px: the weather popup was 378 logical px tall, 472.5 device
  px at 1.25, so the compositor resampled its buffer and the bottom border
  came out as a faint quarter-lit row (2026-09-29). Bar popups and tooltips
  set `wantedWidth`/`wantedHeight`; `AnchoredPopupWindow` rounds the surface
  up, and `HoverPopup` keeps its content at the wanted size, so the slack is
  bottom/right padding rather than a stretched layout. Rounding down instead
  clips the border. The scale comes off the anchor's bar window
  (`notes/quickshell-quirks.md`). The toast stack and the OSD size their
  surfaces the same way: the toast was 434 wide (542.5 device px) and its
  left border split across two columns. A bordered item's own size needs
  `snap()` too, or its two edges can't both be on the grid: the OSD pill's
  66px is 82.5 device px, so one of its top and bottom borders always split.
  The bar is the exception, on purpose: 25px is 31.25 device px, which only
  leaves a faint quarter-lit row under its 3px stripe (see `## Rejected`).

- **`StyledText` asks for `Font.PreferVerticalHinting`; don't "upgrade" it to
  full.** Qt Quick's native text path loads glyphs *unhinted* unless an item
  states a preference — fontconfig's system-wide `hintslight` reaches waybar
  and GTK, never a `QQuickText` — so without this the bar was the one surface
  on the desktop rendering unhinted. `PreferFullHinting` is measurably crisper
  and was tried on the live bar for exactly that reason; it mangles Inter at
  12px and was reverted the same day. Both measurements and the artifact list
  are in `notes/text.md`. Any `FontMetrics` measuring the
  same face needs the same preference, or its advances don't match what gets
  drawn (`Workspaces.qml`).

- **A workspace button is its label plus padding, with a minimum width**,
  both tuned by eye for a comfortable button (`targetPreferredWidth` in
  `Workspaces.qml`).

- **`.modules-left`/`.modules-right`'s 12px border is one-sided**, only on
  the inner/center-facing edge. Anchor the inner RowLayout to the flush
  edge, not `centerIn`, or the flush edge gets a spurious extra 12px too.

- **Screen edges aren't symmetric by construction.** Every module has both
  6px padding and 4px margin on each side — easy to model only the padding
  half. This only shows up on the two modules flush against the true screen
  edge (`Mpd` left, `Clock` right) — elsewhere `RowLayout` spacing hides it.
  Fixed via `Theme.moduleOuterMargin` (4px), added only where a flush
  module actually needs it (the right `ModuleGroupRow`'s `outerMargin` in
  `Bar.qml`; not the left one's, since Mpd's own icon glyph bearing already
  covers it — adding it there would overshoot). **Lesson:** a spacing rule
  can have multiple additive parts; modeling only one can still look right
  almost everywhere by luck, and only fail at edge modules with no neighbor
  to hide behind.

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


## Visual polish beyond the base design

- Every module eases `implicitWidth` through a `FrameSpring` (see
  notes/rendering.md) on content-size changes, which reflows the whole bar
  smoothly for free.
- `Workspaces.qml`'s focus highlight is a single shared `selection`
  Rectangle that slides/resizes between delegates, with labels kept as a
  separate static top layer so only the square moves.
- Hovering a workspace pill shows a live preview of that workspace
  (`shared/popup/WorkspacePreviewPopup.qml`); clicking closes it.

## Rejected

- **Snapping the popup frame down inside its surface** (2026-09-29), first
  try at the weather popup's thin bottom border: size the frame `Rectangle`
  to the device pixel below the surface edge. It put the top and left borders
  on the grid, but the bottom stayed faint: the surface itself was 472.5
  device px, and a resampled buffer has no whole last row to snap to. The
  surface size has to be on the grid, hence `snapSurface()`.

- **Snapping the bar's surface** (2026-09-29). Rounding it up like the
  popups (28 at 1.25) would need an explicit exclusive zone so windows don't
  move, an input mask so the transparent strip passes clicks, and autohide
  kept on the designed height. At a scale like 13/12 the strip would reach
  11px down over windows. All of that to remove a faint quarter-lit row
  under a 3px stripe; the user judged it a hack. Changing the design height
  to a multiple of 4 was rejected too: it only fits some scales.
