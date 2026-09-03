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
                      (BacklightService, MpdService, NotificationService,
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
`backlight`, `volume`, `notifications`, `clock`; only `DP-1` (in `mainScreens`)
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
