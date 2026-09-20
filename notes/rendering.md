# Rendering, animation, and refresh rate

## Current state

This machine drives three outputs from one Quickshell process — DP-1 at
239.99Hz, DP-2 at 144Hz, HDMI-A-1 at ~60Hz — and animation smoothness on DP-1
was the symptom behind most of this file.

There were **two independent 60Hz caps**, found ten days apart. Both are fixed,
and each fix is load-bearing on its own:

| Cap | Mechanism | Fix |
|---|---|---|
| `QQuickSpringAnimation` integrates on its own fixed timestep, no matter how often it is ticked | inside Qt's spring implementation | `shared/animations/FrameSpring.qml` — a hand-rolled ODE on `FrameAnimation` |
| Qt's `QSGAnimationDriver` reads its vsync interval off the wrong screen, trips a broken-vsync heuristic, and drops **all** GUI-thread animations process-wide to a ~60Hz system timer | Quickshell never sets the real `QScreen` on layer-shell windows | `//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1` in `shell.qml` |

Neither fix subsumes the other — measured, see below. `shell.qml` also pins
`//@ pragma Env QSG_RHI_BACKEND=vulkan`, which is purely a memory win and
changes nothing about animation.

Three standing rules fall out of all this:

- **Anything that ticks per frame must be gated on having something to do.** A
  running `QAbstractAnimation` re-renders and swaps a buffer every frame
  process-wide, whether or not a pixel changed.
- **Round spring output that feeds a non-antialiased edge.** At 240Hz the
  rounding shimmer is visible; at 60Hz it hid inside the motion.
- **Coupled springs need one shared clock** (`SpringGroup`), not one
  `FrameAnimation` each.

## FrameSpring

`shared/animations/FrameSpring.qml` is a trimmed port of DankMaterialShell's
`Common/SpringMotion.qml`: it integrates the mass-spring-damper ODE itself
(semi-implicit Euler, `1/240`s sub-steps) and drives it with
`QtQuick.FrameAnimation`, which fires once per *actually rendered frame* and
reports the true elapsed `frameTime` — rather than `QUnifiedTimer`'s fixed
~60Hz GUI-thread ticker.

Stiffness/damping/mass default to Hyprland's own spring config
(`FrameSpring.qml`'s own `stiffness/damping/mass` = 460/35/0.6), **not** the
old `Theme.springSpring/springDamping` (since removed) — those tuned Qt's
`SpringAnimation` formula specifically and did not share Hyprland's unit
convention despite the same underlying ODE shape. FrameSpring implements that
ODE directly, so Hyprland's physical constants are the correct values here.

It is in use everywhere a module's `implicitWidth` is eased (Submap, Backlight,
Clock, Tray, Volume, NotificationCenter, Mpd, Weather, Privacy's `PrivacyIcon`),
across Workspaces.qml's whole spring set, and on the notification panel's slide.
`WidthSpring.qml`/`WorkspaceSpring.qml` (the old `Behavior`/`SpringAnimation`
types) were kept as a fallback for a while, then deleted in 60cd6e2.

### Bind `to:`, don't drive it by hand

`FrameSpring` has an optional `to` property: bind it and the spring snaps to the
initial value on creation and retargets on every change. `snapTo()`/`retarget()`
remain for the springs with no single resting expression (the toast stack's
entry animation, the mpris card's direction-dependent slide). `NaN` is the unset
sentinel — 0 would force a resting target of 0 on those imperative springs.

This replaced a four-step manual ritual, and the reason it is a type feature
rather than a documented convention is that **two of those four steps failed
silently**: no `Component.onCompleted: snapTo(...)` and the module animates in
from width 0 on every reload; no `onTargetWidthChanged: retarget(...)` and the
width freezes at its startup value forever, nothing logged either way.

(A base type's `Component.onCompleted` and a call site's own both run, base
first, no shadowing — that is what lets the imperative call sites keep their
handlers while the base's is a no-op for them.)

### SpringGroup: one clock, declaratively gated

Workspaces.qml has five coupled springs (pill width, each delegate's width, the
selection indicator's `x` and width). Giving each its own `FrameAnimation` made
the selection indicator visibly wobbly **on DP-1 only**.

Independently-clocked springs measure their own elapsed time, and a per-frame
`console.warn` of `value`/`target`/`velocity` showed three Workspaces instances
chasing an identical target reporting values that differed in the 2nd decimal
place at the "same" moment. Old `Behavior`/`SpringAnimation` never had this:
every instance shared Qt's one `QUnifiedTimer` and advanced by the exact same
`dt`, keeping the pill, the delegates and the selection square (overlaid
pixel-for-pixel on its focused delegate) locked together.

`shared/animations/SpringGroup.qml` owns one `FrameAnimation` and calls
`advance(frameTime)` on every registered spring in one `onTriggered`. Springs
join by declaring `group: someGroup` and register themselves on creation, so
nothing outside a Repeater delegate needs to reach in.

The group is gated **declaratively** — `running: group.anyRunning`, where
`anyRunning` scans the registered springs' own `running` flags, the same state
`advance()` clears when a spring settles. The first version of this gating was
imperative (start on retarget, stop when nothing runs) and worked, but had two
touch points: adding a sixth spring while forgetting the stop side would freeze
animations mid-flight. Binding to the springs' own state leaves one source of
truth and no half to forget. DankMaterialShell gates every `FrameAnimation` in
its tree the same way.

Two subtleties, both about destruction. A spring destroyed mid-animation (a
workspace closed while its pill is still easing) emits no `runningChanged`, so
`anyRunning` would never re-evaluate and the driver would stay on forever. **And
a destroyed QObject sitting in a JS array is not null** — it is a stale wrapper
that throws `TypeError: Property 'advance' of object TypeError is not a
function` on any property access, so an attempt to prune "null" entries from
inside `onTriggered` threw every frame instead of pruning anything. Both are
solved by `FrameSpring` unregistering itself in `Component.onDestruction`. Don't
try to detect a dead QObject by truthiness.

### Round the output into non-antialiased edges

`wsDelegate` and `selection` both set `antialiasing: false` deliberately (flush
square buttons, avoids a 1px seam). Feeding a continuously-varying unrounded
spring float into `Layout.preferredWidth`/`width`/`x` on such an edge means
consecutive frames can round to different device pixels even while the
underlying value moves smoothly — a rounding shimmer, not motion jitter. It
existed under the old 60Hz-capped system too; genuine 240Hz sampling just hits
the boundary four times as often. Every consumption of a Workspaces spring's
`.value` is wrapped in `Math.round()`.

**Dead end, instructive.** Before finding the rounding bug, the wobble was
assumed to be underdamped overshoot and the damping ratio was pushed from ζ≈1.05
to ζ≈2. The user reported this made it *worse* — which alone disproves the
overshoot theory, since more damping can only ever reduce real oscillation.
(Why: for this discrete integration, increasing damping past a point lengthens
the slower of the two decay eigenvalues, making the settle tail linger.)
**Lesson: a fix that only makes sense if your diagnosis is right is itself a test
of that diagnosis.** When it moves the symptom the wrong way, that is a real
result — the knob isn't the mechanism, and it doesn't need a bigger turn.

## Idle cost: an always-running FrameAnimation is ~8% CPU (2026-09-06)

`qs` sat at a constant 7-8% of a core doing nothing. Workspaces.qml's shared
driver was declared `running: true` unconditionally, on the reasoning that
`advance()` on a settled spring is a cheap early-return no-op.

**That reasoning is wrong, and the mistake generalises: the callback's cost is
not the cost.** A running `FrameAnimation` is a running `QAbstractAnimation`, so
for as long as it lives Qt Quick requests an update, runs polish+sync,
re-renders the scene graph and swaps a buffer every frame, whether or not a
pixel changed. Measured on eDP-1 at 90Hz: ~90 wayland commits/s and ~240 GPU
ioctls/s at idle, 48% of profile samples in `QSGRenderThread`. Gated: **zero**
commits, 0.2% CPU.

This is process-wide, not window-local — see `notes/battery.md` for the same
class of bug costing the *sum* of all three outputs' refresh rates.

(DMS's other answer to coupled springs, `VectorSpringMotion`, integrates several
scalars inside one spring object — clean for a fixed component set like its
island's geometry, but it hand-unrolls every component through every function,
so it doesn't fit Workspaces' per-delegate springs, whose count varies with the
workspace list.)

## Why animations were capped at 60Hz

### Cap 1: QQuickSpringAnimation's own timestep (2026-09-03)

First investigation, from a user report that the control-center slide looked
stuttery on DP-1. `QSG_RENDER_TIMING=1` showed the panel's `QQuickWindow` doing
`polishAndSync`/`syncAndRender` at a rock-steady ~15-16ms throughout the spring,
never near the ~4ms a 240Hz output allows. Render/swap times were 0ms, so the
GPU and compositor were not the bottleneck.

`QSG_FIXED_ANIMATION_STEP=0` (found via `strings` on `libQt6Quick.so.6`) had
**zero effect** — identical 15-16ms distribution — so that knob controls the
*delta* used per tick, not the tick rate.

This section originally concluded **"no shell-side fix exists"**. That was
wrong, twice over. It was true only for that one mechanism —
`Behavior`/`SpringAnimation` riding `QUnifiedTimer` — not for QML animation in
general. DankMaterialShell doesn't use `Behavior`/`SpringAnimation` for spring
motion at all, which is where `FrameSpring` came from.

### Cap 2: Qt paces animations off the wrong screen (2026-09-12)

The panel slide still looked laggy on DP-1 after the FrameSpring rollout. Not
lazy loading (`NotificationCenterPanel` is instantiated eagerly in `shell.qml`),
and not the spring maths — FrameSpring cannot create frames nobody asked for.

Measured in an isolated `qs -p` instance holding only the panel (scratch config
symlinking `shared/`, `services/`, `modules/`, so the live shell was untouched):

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

16.68ms is **HDMI-A-1's** 59.95Hz. A `Screen.name` probe inside a `PanelWindow`
whose Quickshell `screen` is DP-1 prints `qtScreen=HDMI-A-1 qsScreen=DP-1`:
**Quickshell's layer-shell windows never update `QWindow::screen()`, so every
one of them looks like it is on Qt's primary screen.** `QSGAnimationDriver`
takes its expected vsync interval from that screen, sees real frames arriving
every 3.3ms on DP-1, concludes vsync throttling is broken (measured <
expected/2) and switches all GUI-thread animations, process-wide, to a ~60Hz
system timer.

`FrameAnimation` is a GUI-thread animation, so it ticks once per *rendered*
frame — and the render loop had stopped asking for more than ~60 of those per
second. FrameSpring fixed the pacing *source*; it never had a say over the frame
*rate*.

**Fix: `//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1`.** The simple driver
has neither the refresh-rate guess nor the broken-vsync heuristic. Same harness,
same method:

| | frames per open+close | interval | `FrameAnimation.frameTime` | 1000ms `NumberAnimation` |
|---|---|---|---|---|
| before | 74 | median 15ms | 16.01ms (accurate, but 60/s) | 961ms wall |
| after | 532 | median 4ms | 4.17ms (accurate, 240/s) | 1003ms wall |

Not a trade: timed animations get *more* accurate (the system-timer fallback ran
them ~4% short), idle cost is unchanged — 0 frames and 0 CPU ticks over 3s with
the panel open, since the gating above still holds — and one open+close cycle
costs 8-9 CPU ticks instead of 4. Roughly 4x the frames for 2x the CPU, only
while something moves.

The pragma takes effect **only at process start**; a hot reload keeps the old
driver, so A/B testing it needs a full kill and relaunch. Plain comment lines
between `//@ pragma` lines parse fine, so the reasoning lives next to the pragma.

### The two fixes are not interchangeable

The obvious follow-up is whether the pragma lets us drop FrameSpring and go back
to `Behavior { SpringAnimation {} }`. It does not. Same harness, one process per
driver, 500px travel on a plain Rectangle's `x`, counting property updates:

| | default driver | with the pragma |
|---|---|---|
| `Behavior { SpringAnimation }` | 62 updates/s | **62 updates/s** |
| `Behavior { NumberAnimation { duration: 500 } }` | 63/s (480ms wall) | **241/s** (503ms wall) |
| `FrameSpring` | ~60 frames/s | **~240 frames/s** |

`NumberAnimation` tracks the driver, so every duration-based animation in the
shell got faster and more accurate for free. `SpringAnimation` does not move at
all: ~62 updates/s with a driver ticking at 240Hz, in the same process and run
where `NumberAnimation` managed 241/s. That isolates the cap inside
`QQuickSpringAnimation` itself. Dropping FrameSpring would put every spring back
at 60Hz while everything around it ran at 240Hz.

### Upstream, not fixed here

The root cause of cap 2 is Quickshell not setting the real `QScreen` on its
layer-shell windows. With that fixed, Qt would compute 4.17ms, the heuristic
would never trip, and the default driver would be fine. Worth reporting
upstream; the pragma is the local workaround.

## Vulkan RHI backend (2026-09-12)

`//@ pragma Env QSG_RHI_BACKEND=vulkan` is pinned in `shell.qml`. It is a memory
win and **that is the only thing it changes**.

Synthetic harness, 6 layer-shell windows across all 3 screens (a full-width bar
plus a 400x300 popup per screen), RSS at t=7s, three reps per backend:

| backend | RSS |
|---|---|
| opengl | 258 / 256 / 257 MB |
| vulkan | 168 / 169 / 171 MB |

~88MB, ~34%. The cost is **per-window**, which is why it matters here: scaling
the same harness from 1 to 6 windows cost OpenGL ~12.6MB/window and Vulkan
~3-8MB/window. The real shell (12 `Creating QRhi` windows) came up at 280MB on
Vulkan against 346MB on OpenGL — directionally the same, but that 346MB was a
long-uptime process against a fresh 280MB, so the three-rep table is the real
evidence, not that pair.

CPU was slightly lower (22-25 vs 28-29 ticks over 5s of continuous animation),
close enough to noise not to claim.

**It replaces neither animation fix.** The hope was that Vulkan would report a
sane vsync interval and stop the heuristic tripping. It does not — the root
cause is the unset `QScreen`, which has nothing to do with the RHI backend:

```
opengl: broken vsync throttling (3.142857 < 8.340144)
vulkan: broken vsync throttling (4.000000 < 8.340144)
```

And the spring cap is inside `QQuickSpringAnimation`'s own timestep, which the
backend cannot see:

| | opengl | vulkan |
|---|---|---|
| `NumberAnimation`, default driver | 60/s | 60/s |
| `NumberAnimation`, simple driver | 240/s | 237/s |
| `SpringAnimation`, default driver | 60/s | 60/s |
| `SpringAnimation`, simple driver | **62/s** | **62/s** |

**`ScreencopyView` works on Vulkan** — the one real risk, since the dmabuf
import is backend-specific (`eglCreateImage` for GL,
`QVulkanDeviceFunctions::vkCreateImage` for Vulkan; Quickshell 0.3.1 implements
both). Verified with a live `captureSource: Quickshell.screens[0]`:
`hasContent=true` and a correct 1440x2560 `sourceSize` on both. RADV advertises
`VK_EXT_external_memory_dma_buf` and `VK_EXT_image_drm_format_modifier`, which
is what that path needs.

**Caveats.** `radv is not a conformant Vulkan implementation, testing use only`
prints at every startup and is harmless. Vulkan recreates the swapchain on every
window resize (`Creating recycled swapchain of 3 buffers`), which GL has no
equivalent step for — worth remembering if the adaptively sized notification
popups ever look janky. Presentation mode is FIFO (vsync). The 3-image swapchain
means a *very* large window would cost more than GL's 2 buffers; nothing here is
near that size.

## Measuring any of this

See `notes/method.md` — the reload settle time, the stdout buffering trap, and
what a per-frame `console.warn` actually counts are all there, and getting any
of them wrong invalidates a whole measurement round.
