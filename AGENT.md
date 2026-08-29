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
                      source of truth for colors so modules never hardcode hex
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

Monitor layout is machine-specific and can change; re-check with
`hyprctl monitors -j` rather than trusting old notes. At time of writing:
`DP-2` at (0,0) 2560×1440, `HDMI-A-1` at (5632,0) 2560×1440 (rotated),
`DP-1` at (2560,0) 3840×2160 — `DP-1` is the one with tray/privacy/weather.
