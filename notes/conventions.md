# Conventions and tooling

## Comments and docs

Keep **code comments** short and concise. A comment earns its place by saying
*why*, not by restating what the line already says — one to four lines, no
prose blocks above every property, no retelling of the debugging session that
produced it. Delete a comment that's gone stale rather than growing it.

**Don't explain code by comparing it to swaync, waybar, or whatever else this
replaced.** A reader of the code has no access to those configs, and the
comparison dates fast. State the behavior or the intent — "the panel lists
these already, so the toast would be redundant", not "swaync hides its toasts".
Provenance for a measured constant belongs in `notes/`, not at the call site.

**The `notes/` files are the exception**: they're written for agents, so the
long-form explanation belongs there — measurements, rejected alternatives,
the reasoning behind a non-obvious choice. A code comment states the rule and, where the
reasoning is long, points at the `notes/` file that carries it.


## Refactor pass against DankMaterialShell and Noctalia (2026-09-06)

Both projects were re-read side by side with this repo — DMS (`/tmp/DankMaterialShell`,
636 QML files) and Noctalia, which is now a **C++** shell (`/tmp/noctalia`, 684
headers / 577 .cpp, meson, no QML at all), so only its design is transferable,
never its code. Most of both is scope this bar deliberately doesn't have
(DMS's `SettingsData` alone is 3570 lines, plus a plugin system and a widget
registry; Noctalia ships a user-facing TOML config with a validation schema).
What follows is what was actually worth taking.

### `BarModule`, `StyledText`, `Icon`

Modelled on DMS's `Modules/Plugins/BasePill.qml` (every DMS bar widget is a
`BasePill { content: Component { … } }`) and its `StyledText`/`DankIcon`.

`BarModule` deliberately uses **plain inheritance, not** DMS's
`default property alias content: <inner>.data`. DMS needs the alias because
`BasePill` wraps content in a background + ripple + Loader; this bar has no
such chrome, and an alias here would silently reparent each module's
`MouseArea`/`Timer`/`PwObjectTracker` into a nested item and change what
`anchors.fill: parent` means.

Two modules don't use it, on purpose: **Workspaces.qml** rounds its spring
output and drives five coupled springs off one `SpringGroup`; **Privacy.qml**
springs its per-app icons rather than its own width. A base type doesn't have
to be universal. (**Submap.qml** used to override `padding` and
`implicitHeight` for an accent chip of its own; the pill and its text
colour are now its `ModuleGroup`'s, set in `shell.qml`'s layout.)

A module's text colour is `root.textColor`, never `Theme.groupText`
directly: `ModuleLoader` binds it to the group's `textColor`, so a module
placed in a coloured group (the cream submap one) reads against it without
knowing. `Icon` still defaults to `Theme.groupText` for the popups, so a
bar glyph passes `color: root.textColor` explicitly. A module that draws its
own chip keeps picking its own pair, as the old Submap did; a state colour
(Battery's critical red) overrides with `textColor` as the fallback.

### `pragma ComponentBehavior: Bound`, everywhere

DMS has it in 225 of its 636 files. It's the compiler-level guard for this
file's worst documented bug class — an unqualified `modelData` in a delegate
resolving to an ancestor's instead of the delegate's own, silently, with wrong
data and no warning. Every delegate in this repo already declared its required
properties, so the rollout was clean; `shell.qml`'s `Variants` delegate got an
`id: bar` so its model access is qualified too.

### `MprisService`

~90 lines of player-selection policy (`mprisPlayers`, `mprisIndex`,
`defaultMprisIndex()`, `prev`/`nextMprisPlayer()`, slide direction, the
`suppressPop` flag) lived inside `NotificationCenterPanel.qml`, which had this
repo's own services/views split backwards. Moved to `services/MprisService.qml`,
mirroring DMS's `Services/MprisController.qml` (though ours is much thinner —
a selection cursor over `Mpris.players`, not a media abstraction). The panel
went 718 → 642 lines.

### `scripts/lint.sh` — and why there's no formatter

`qmllint` can't resolve `qs.*` imports on its own (Quickshell synthesises that
module at runtime; there are no qmldir files on disk), so every cross-file type
came back unknown and drowned the real findings. `scripts/lint.sh` builds a
throwaway shim tree of qmldir files + symlinks describing the same layout,
points qmllint at it with `-I`, and deletes it after.

It found six real problems on its first runs: four unqualified accesses
(`ModuleGroup.qml`, `Workspaces.qml`, both of `Weather.qml`'s forecast
delegates), `Tray.qml` reading a delegate's `modelData` through an `Item`-typed
handle (fixed by tracking the `SystemTrayItem` separately from the delegate it
anchors to — two different things that were conflated), and
`NotificationService.qml` reading fields off an untyped `createObject()` result
(fixed with `as NotifWrapper`, which was already a named type). `ModuleLoader`
also picked up `(item as Item)?.implicitWidth`.

**Nothing is suppressed by category.** A first version of `.qmllint.ini`
demoted whole categories (`MissingProperty`, `MissingType`, …) to `info` to get
a green run — which meant a genuine missing property anywhere would have been
downgraded to chatter, *and* left 28 lines of noise on every run, so clean and
broken looked identical. Instead every category stays fatal and `scripts/lint.sh`
carries an explicit list of individual known-unfixable findings, each with its
reason (`--all` prints them). 25 are suppressed today: 22 are gaps in
Quickshell's own qmltypes — `PanelWindowInterface` is literally
`isCreatable: false` in `quickshell-window.qmltypes`, and `Margins`, `Edges`,
`PopupAnchor`, `PopupAdjustment`, `QProcess::ExitStatus` and the
`NotificationAction` list type aren't exported — and 3 are deliberate
duck-typing (`Loader.item` in ModuleLoader, twice, `Repeater.itemAt()` in
NotificationPopupWindow), where the type-safe alternative would mean forcing
every placeable module onto one base class that Workspaces shouldn't be on.

Verified it still bites: injecting an unqualified `modelData` into a Weather
delegate and a typo'd `Theme.groupTxt` into Volume made it report exactly those
two and exit 1.

`.githooks/pre-commit` runs it. **Not** enabled automatically — turn it on with
`git config core.hooksPath .githooks`.

**No formatter is wired up, deliberately.** DMS uses `qmlfmt` (not packaged
here); Qt's own `qmlformat` disagrees with this repo's style badly enough to be
a regression — it explodes `Bar.qml`'s deliberate one-line
`Component { id: x; Y {} }` declarations into four-line blocks and re-indents
object literals. Everything else in the tree already matches `qmlformat`
output, so if it ever gains a way to leave those alone, revisit.

### Considered and not done

- **Dropping `MpdService` for `Quickshell.Services.Mpris`** (one fewer
  permanent `mpc idleloop` subprocess, ~109 lines). Left alone at the user's
  request; also note `mpd-mpris.service` is currently *inactive* on this
  machine, so it would need enabling first, and the bar module would then show
  any MPRIS player rather than MPD specifically.
- **Deleting `WidthSpring.qml`/`WorkspaceSpring.qml`.** Was kept as a
  documented fallback for a while; deleted in 60cd6e2 once FrameSpring had
  proven itself.
- **DMS's `Ref.qml` / `addRef`/`removeRef` service refcounting.** Buys nothing
  here — Quickshell instantiates `pragma Singleton` lazily, so a service whose
  module isn't in any screen's layout never starts in the first place.
- **`//@ pragma Env` for Qt tunables.** DMS pins `QSG_RENDER_LOOP=threaded` and
  friends in its `shell.qml`. Originally declined as speculative; `shell.qml`
  now pins `QSG_USE_SIMPLE_ANIMATION_DRIVER=1` and `QSG_RHI_BACKEND=vulkan`,
  each measured first — see `notes/rendering.md`. The principle stands: neither
  was set speculatively. `//@ pragma AppId` *was* added.

