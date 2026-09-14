# Style notes

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


## Visual polish beyond the base design

- Every module eases `implicitWidth` (`Theme.qml`'s `resizeDuration`) on
  content-size changes, which reflows the whole bar smoothly for free.
- `Workspaces.qml`'s focus highlight is a single shared `selection`
  Rectangle that slides/resizes between delegates, with labels kept as a
  separate static top layer so only the square moves.
- Hovering a workspace pill shows a live preview of that workspace
  (`shared/popup/WorkspacePreviewPopup.qml`); clicking closes it.

