# AGENTS.md

A Quickshell status bar with a fixed visual identity (dark bar, teal accent,
pill-shaped module groups) and a fixed per-monitor module layout. Not meant to
grow new features beyond what's already here unless asked.

**Source of truth for any visual value is `shared/Theme.qml`** — the palette +
metrics singleton (colors, padding, radii, border widths, font sizes, spring
defaults and the distances a gesture covers). It wins over any prose, including
these notes. A *gesture's own* spring tuning is the exception and stays at its
call site, next to the comment that says why it is what it is; the one pair two
surfaces share lives in `NotificationTheme.qml`. See `notes/rendering.md`.

## Keep this file short

This file is a router, nothing else. It stays under ~60 lines. Anything longer
than a line — a measurement, a rejected alternative, the reasoning behind a
non-obvious choice — goes in the matching `notes/` file, not here. When a note
grows a new subject, add a `notes/` file and one row below; don't inline it.

Notes are written for agents, so long-form belongs there: measurements,
rejected alternatives, why something is the way it is. Code comments stay short
and say *why* (see `notes/conventions.md`).

## Read before writing code

| File | Covers |
|---|---|
| `notes/layout.md` | File tree, what each module/service/shared type does, the `qs.*` import rule, per-screen module layout |
| `notes/conventions.md` | Comment style, `BarModule`/`StyledText`/`Icon`, `pragma ComponentBehavior: Bound`, `scripts/lint.sh`, ideas considered and rejected |
| `notes/style.md` | Visual rules beyond Theme.qml: bar geometry, group/pill construction, spacing, easing on width changes |
| `notes/qml-gotchas.md` | QML and Quickshell traps already hit here — binding cascades, Loader visibility, anchoring re-fire |
| `notes/limitations.md` | Per-module known limitations, and which are deliberate |

## Read when touching a subject

| File | Covers |
|---|---|
| `notes/rendering.md` | Animation and refresh rate: the 60Hz cap and its two real fixes, `FrameSpring`, idle-CPU cost of running animations, Vulkan RHI |
| `notes/text.md` | Font weight via Inter's `wght` axis, hinting, blur caused by rendering into a layer |
| `notes/panels.md` | Control center: per-screen placement, slide animation, visibility races, click-triggered popups |
| `notes/notifications.md` | Native notification daemon replacing swaync, and its IPC |
| `notes/osd.md` | Native OSD replacing swayosd, incl. lock-key reads and contrast over bright windows |
| `notes/battery.md` | UPower port from waybar, and the no-battery blink that cost 3.2% CPU |
| `notes/backlight.md` | `BacklightService` sysfs reads and inotify |
| `notes/privacy.md` | Mic vs. screencast detection by PipeWire media class |
| `notes/workspaces.md` | Hover previews via per-window screencopy |
| `notes/method.md` | How to screenshot and verify visually, probe a running shell, and measure CPU/frames without fooling yourself |
