# QML gotchas

QML and Quickshell traps hit in this repo. Upstream bugs with a local
workaround are in `notes/quickshell-quirks.md` instead.

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
  *that* instead — see `Mpd.qml`'s `contentVisible` and
  `ModuleLoader.qml`'s `hasContent`.

- **A Repeater delegate type that declares *any* `required property` stops
  receiving the legacy ambient `modelData`/`index` context properties
  entirely** — Qt switches that delegate to required-property-only
  binding, so an unqualified `modelData` reference inside it (or in the
  expression assigning one of its other properties) silently falls through
  to an unrelated ancestor's `modelData` instead (in this repo: the bar's
  own screen, from shell.qml's `Variants`), rather than the Repeater's own
  item. No warning — just wrong data, and `console.warn`-style guards see
  the wrong value passed in. Hit in `shared/bar/ModuleLoader.qml` (needs
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

- **`ShellRoot` takes no attached objects**: `Component.onCompleted` on it
  is not a lint error but a load-time one — `Non-existent attached object` —
  which takes the whole config down. And `Connections` resolves under
  `import QtQuick`, not `import QtQml`; qmllint accepts the latter, the
  runtime rejects it with `Connections is not a type`. Both leave the running
  shell on its last good config, so a change that "did nothing" is worth
  checking against `qs log -i <id>` before it is worth debugging. (Found
  building the OSD, 2026-09-12.)

- **`PersistentProperties` only persists as a child of a Quickshell
  `Singleton`/Scope** (probed 2026-09-28, Quickshell 0.3.1, with a `qs -p`
  config that sets a value, then reloads). In a `QtObject` singleton — this
  repo's usual service shape — it silently resets on every reload; still
  resets as a `property PersistentProperties x: …` inside a `Singleton`;
  persists only as a *direct child* of a `Singleton`. The restored value
  arrives via its `reloaded` signal just after creation, so read it through a
  binding (an alias), not once in `Component.onCompleted`, which still sees
  the default. `NotificationService` is the one `Singleton` here for this.

- **`transient` is a reserved word** in QML: `property bool transient` is a
  load error that takes the whole singleton down, and with it every file
  using it. qmllint catches it; run `scripts/lint.sh` before a reload does.

- **Quickshell's Hyprland `active` ≠ the single system-wide focus.**
  `active` is focused per monitor (true on N monitors at once); `focused` is
  the one system-wide focused workspace. Use `modelData.focused` for the
  single accent highlight.

- **`HyprlandWorkspace` has no `windows`/`empty` property.** Count its
  `toplevels`, filtered on `t.workspace` (see `notes/quickshell-quirks.md`),
  not `lastIpcObject.windows`: that is a snapshot and goes stale.
