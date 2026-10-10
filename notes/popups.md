# Hover popups: unfold and fold (2026-10-10)

The hover popups (Clock's calendar, Weather's forecast, Privacy's app list,
the workspace preview) used to appear and vanish outright. They now unfold
out of the bar and fold back into it, in `shared/popup/HoverPopup.qml`. The
gesture is the OSD pill's rise turned upside down (`notes/osd.md`), cut down
to one stage, because these are bar surfaces (the `Theme` palette), not
floating ones, and the bar keeps a still look (`notes/style.md`).

## The gesture

- **Open:** the plate's height springs from a strip as tall as its two
  corners (20px) to the resting height. Under damped, ζ ≈ 0.68
  (230/16, mass 0.6), so it runs ~5.4% past and settles back. The content
  stays laid out at full size, is clipped by the plate, and fades in
  over `Ramp.reveal()` (0.45 → 0.80 of the opening, shared with the OSD).
- **Fold:** after the 200ms grace period the plate folds back up at
  ζ ≈ 1.08 (260/27), so it reads as one stroke with no wobble. It is aimed
  half the travel past the strip, so it doesn't decelerate into the bar, and
  parks the moment it reaches the strip (the OSD drop's trick). The aim is
  at least a strip's height past: aimed at the strip itself, a plate with no
  travel would never start, so never park, dismiss, or release the bar's peek.
- **No wind-up on the fold.** A popup folds because the cursor left, after a
  200ms grace already, and a hop on top would delay it further. Not tried.
- **`close()` stays instant** (takeover by `PopupCoordinator`, a click via
  `HoverPopupArea.cancel()`): the next popup, or the click's own result, is
  the feedback, and two popups would otherwise be on screen at once.
- **Re-hover mid-fold reverses** from wherever the plate is: the popup is
  still built, `HoverPopupArea` sets `anchorHovered` on it, and the spring's
  `to` flips back. The coordinator stays pointed at a folding popup until it
  parks, so the bar's peek holds and a takeover still `close()`s it.

Measured on DP-1 (weather popup, 380px plate, 4.1ms frames from a
`frameSwapped` probe): open 20 → 398 (peak) → 380, settled by ~380ms; fold
~130ms; a re-hover at 117px went back to 380 with one `dismissed` at the end.

## Details that matter

- **Held at the strip until the window's first frame** (`_presented`, off
  the plate window's `frameSwapped`). The window is built when the hover
  dwell ends, and its first frame took ~12ms; a spring released on the hover
  had run ~50px before anything was on screen, which read as a stutter at
  the start of a 240Hz animation. Now the first frame is the strip, then a
  13ms gap there, then 4ms frames.
- **Surface slack** below the plate (`AnchoredPopupWindow.slackHeight`) is
  6% of the travel: the overshoot is 5.4% at this damping, and a window clips
  its contents. Derived, not fixed, so a tall workspace preview can't clip
  its bottom border at the peak. The input `mask` is the resting rect, so the
  slack doesn't take clicks; during the ~150-200ms of motion the transparent
  part above a shorter plate does, accepted.
- **The plate's height goes through `Screens.snap()`**, so the bottom border
  stays one solid row while it moves (`notes/style.md`).
- **The content is never `visible: false` at opacity 0**, unlike the OSD's
  `detail`. `ScreencopyView` gates its capture on its effective visibility
  (`WorkspacePreviewPopup.qml`), so hiding the content made the preview's
  windows start capturing only halfway open and pop in blank, and dropped
  every capture below 45% on the fold. Opacity 0 already skips drawing.
- **`isShown`, not `isOpen`**, is what a subtype narrows `visible` with: it
  stays true through the fold. `_open` is "hovered or in grace".
- **Park order:** `_shown` is cleared before `snapTo()`, which changes
  `value` again and re-enters `onValueChanged`; the other order would emit
  `dismissed` twice.

## Hyprland

Hyprland 0.56.2 (read in its source) never fades a *layer's* popups in: the
renderer draws them with the layer's alpha, not the popup's
`fadePopupsIn` value, which only window popups use. On unmap it does fade a
snapshot out with `fadePopupsOut` (inherited from `fadeOut` here), and that
path ignores the layer's `no_anim`, so a `no_anim` layer rule on
`quickshell-bar` would change nothing for popups. What fades is the last
frame, the 20px strip, for ~300ms. Accepted by the user; hiding the plate
below the strip before unmapping would blank the snapshot if it ever bothers.

## Not done

- **Tooltips** don't unfold yet. If they do, extract the gesture from
  `HoverPopup` into its own type (like `ControlCenterSlide`) and use a
  stiffer spring: they are small and transient.

## Rejected

- **`no_anim` on the `quickshell-bar` layer** to stop Hyprland fading the
  popups: see Hyprland above, it doesn't reach them.
- **Driving the spring by hand** (`retarget()` from `on_OpenChanged` and
  friends): done first on the reasoning that `to` snaps at creation, which is
  what is wanted here; the bound `to` is shorter and also covers a re-hover
  before the first frame, which the hand-driven version left settling below
  the strip.
