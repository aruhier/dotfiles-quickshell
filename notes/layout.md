# Layout

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
                      Almost all of them are `BarModule`s (see
                      `notes/conventions.md`)
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
                      Privacy.qml deliberately don't use it — see
                      `notes/conventions.md`
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
                         window at its real position — see
                         `notes/workspaces.md` for what makes this work
  PopupCoordinator.qml   pragma-Singleton — only one hover popup open at a
                         time process-wide
shared/osd/OsdWindow.qml the on-screen display: one shared bottom-centre
                      pill for volume/backlight/lock keys, driven by the `osd`
                      IPC handler in shell.qml. Replaces swayosd — see
                      `notes/osd.md`
shared/notifications/ the notification daemon's UI — see
                      `notes/notifications.md` for why this is a separate
                      subsystem from shared/popup/ rather than built on it
  NotificationTheme.qml  pragma-Singleton palette/metrics matching the
                         swaync setup this replaces — deliberately not
                         shared/Theme.qml, see `notes/notifications.md`
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

