# Battery

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


## A machine with no battery blinked an invisible module at 3.2% CPU (2026-09-14)

`qs` sat at ~3.2% of a core with nothing on screen moving — the same *class* of
bug as the always-running-`FrameAnimation` section in `notes/rendering.md`,
but with a completely different cause and a much wider blast radius.

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
