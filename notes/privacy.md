# Privacy indicator

## How `Privacy.qml` works

Two glyphs, mic and screen, each springing its own width in and out; a hover
popup lists the apps behind them.

- **One `PwObjectTracker` over every node** (`nodeTracker`,
  `objects: Pipewire.nodes.values`). An untracked Pipewire node never gets
  its `properties` bound, whatever its media class, so *every* read below
  depends on it — the mic as much as the screen. It deliberately doesn't
  filter on `isStream`, see Rejected.
- **Mic: `media.class === "Stream/Input/Audio"`, exact.** Any open capture
  stream counts; Quickshell's `PwNode` doesn't expose the node's state, so
  open-but-idle can't be told from RUNNING.
- **Screen: a `Stream/Input/Video` consumer *and* the portal's own
  `Video/Source` node** (`screencastPortalActive`). The class alone also
  matches a webcam; the portal node exists only for a cast's lifetime.
- **Apps are merged by a case-folded name**, the app-reported
  `application.name` winning for display, the icon falling back to the key.
- **No service.** It's a reactive scan over the process-wide
  `Pipewire.nodes`, instantiated only on screens whose layout lists
  `privacy` — `mainScreens` in shell.qml, so one instance on the desktop
  (DP-1) and two on a machine with DP-1 and eDP-1 both connected, each with
  its own tracker. (A `PrivacyService` holding one tracker is a pending
  decision from the 2026-09-28 review.)

## What was measured (2026-09-02, 2026-09-08)

Against a live graph on this machine: Firefox sharing a tab through the
portal, then a webcam, with Bluetooth buds connected.

- **Tracked vs untracked is the whole rule.** A `qs -p` probe with
  `PwObjectTracker { objects: Pipewire.nodes.values }` saw a real capture's
  `properties["media.class"]` and `ready` populate and update live; the same
  probe with no tracker reproduced `ready: false, properties: {}` on the same
  live node. `PwNode.type` does stay `Untracked` for `Stream/Input/Video`, and
  `isStream` stays false — Quickshell only sets those for classes it maps to
  a `PwNodeType`, which has no video-stream member.
- **Exact compare, never a prefix.** The headset publishes a permanent
  `bluez_capture_internal` node of class `Stream/Input/Audio/Internal`; a
  prefix match lights the mic whenever the buds are connected. Noctalia
  matches exactly too (`kAudioCaptureConsumerClasses`).
- **Camera and cast consumers are indistinguishable.** Both named `firefox`,
  no `application.name`, differing only in a Firefox-specific `media.name`
  (`webrtc-consume-stream` vs `camera-stream`). The discriminator is the
  producer: `xdg-desktop-portal-hyprland`'s `Video/Source` node appears and
  disappears with each cast, with a fresh session id each time
  (`xdph-streaming-718498`, then `-140892`). The camera's device node
  (`libcamera_input…`, `media.role: Camera`) is permanent, so its presence
  means nothing.
- **One app, two names.** Firefox reports `application.name` "Firefox" on its
  mic stream and none on its video one, whose `node.name` is "firefox". Keyed
  on the raw string that was two rows; case-folded, one.

## Known limits

- **A cast and a webcam at once count the camera as screen.** Separating them
  needs a `PwNodeLinkTracker` per consumer.
- **A webcam alone shows nothing**: a video consumer with no portal node is
  dropped. (Pending decision: a camera glyph.)
- **The portal check knows one portal's naming**: `node.name` starting with
  `xdg-desktop-portal`. xdg-desktop-portal-wlr names its node `xdpw_stream`;
  GNOME and KDE have their own.
- **Capture that doesn't go through PipeWire is invisible**: wlr-screencopy
  (grim, wf-recorder, OBS's wlrobs, this repo's own workspace previews).
- **False mic positives, found in the 2026-09-28 review, not yet fixed.**
  Every record stream pipewire-pulse creates is `Stream/Input/Audio`:
  pavucontrol's peak meters (one per source *and per sink monitor* while its
  window is open), OBS desktop audio, cava, `parec @DEFAULT_MONITOR@`.
  pipewire-pulse tags these with `stream.capture.sink` (target is a sink or
  monitor) and `stream.monitor` (peak detect). Loopback, echo-cancel,
  filter-chain and combine-stream capture halves are permanent
  `Stream/Input/Audio` nodes too; they carry `node.link-group`, app streams
  don't.

## Rejected

- **Polling `pw-dump`** (the old `ScreenShareService` singleton): built on
  the belief that Quickshell could never see a video stream's properties,
  which was the tracking rule misdiagnosed.
- **`PwNodeType.AudioInStream` for the mic**: `PwNodeType` has no video
  counterpart, so the two glyphs couldn't share a mechanism; `media.class`
  covers both, and the exact compare behaves the same on the headset case.
- **A prefix match on `media.class`**: lights the mic for the headset's
  internal node.
- **`Stream/Input/Video` alone as "screen share"**: a webcam matches.
- **DankMaterialShell's `looksLikeScreencast` / Noctalia's
  `kScreenShareNamePrefixes`**: they match the capture node's name, which
  here says nothing about screens.
- **Filtering the tracker to `n.isStream`** (DMS filters to `!isStream`):
  `isStream` is false for a video stream, so either filter's result on the
  node that matters is a coincidence. Proposed and caught again on
  2026-09-08 only by re-measuring.
- **`PwNodeLinkTracker(node: defaultAudioSource)` for the mic**: a capture
  device carries idle internal link groups, which showed the mic as active
  with nothing recording.

## Lesson

An empirical "confirmed" finding can still encode the wrong mechanism. The
2026-09-02 synthetic repro did fail, but the write-up blamed the media class
instead of the variable that mattered (tracked vs untracked), because the
untracked case was never isolated as its own test. When retiring a workaround
built on an old finding, re-run the original failure case alongside the fix.
