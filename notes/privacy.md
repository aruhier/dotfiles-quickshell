# Privacy indicator

## How it works

`services/PrivacyService.qml` scans Pipewire's nodes; `modules/Privacy.qml`
is a thin view: three glyphs, mic, screen and camera, each springing its own
width in and out, and a hover popup listing the apps behind them.

- **One `PwObjectTracker` over every node, for the process** (`nodeTracker`,
  `objects: Pipewire.nodes.values`), in a singleton built on first use — a
  Privacy module — so a layout without one pays nothing. An untracked node
  never gets its `properties` bound, whatever its media class, so *every*
  property read here depends on it. It deliberately doesn't filter on
  `isStream`, see Rejected.
- **Mic: `media.class === "Stream/Input/Audio"`, exact, minus what isn't a
  mic** (`isMicCapture`): streams recording a sink or its monitor
  (`stream.capture.sink`), peak meters (`stream.monitor`, or a
  `media.category` of `Monitor`/`Manager`, which Quickshell itself reads as
  `isMonitor` and native meters like pwvucontrol set) and in-graph plumbing
  (`node.link-group`) — see the 2026-09-28 section below. Flags are strings,
  `"true"` or `"1"` (Quickshell passes `info->props` through as strings). Any open
  capture stream counts; Quickshell's `PwNode` doesn't expose the node's
  state, so open-but-idle can't be told from RUNNING.
- **Screen or camera: a `Stream/Input/Video` consumer, told apart by what it
  is linked from** (`videoSources`, from `Pipewire.linkGroups`, whose
  `source`/`target` are constant node pointers from the registry — no tracker
  needed). A source that is a camera *device* (`device.api` of `v4l2` or
  `libcamera` — not merely set, audio devices carry `"alsa"` — or a
  WirePlumber `v4l2_input.*` / `libcamera_input.*` name, which is readable
  before properties bind) makes it a camera; anything else — any portal's
  screencast stream — a screen. A consumer not linked yet shows nothing.
- **Apps are merged by a case-folded name**; a later node's
  `application.name` and `application.icon-name` win over the first one's,
  and the icon falls back to the key.

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

- **Capture that doesn't go through PipeWire is invisible**: wlr-screencopy
  (grim, wf-recorder, OBS's wlrobs, this repo's own workspace previews), and
  most webcam use — Chromium (its PipeWire camera is behind a flag), Zoom,
  Discord, OBS's V4L2 source and ffmpeg open `/dev/video*` directly. Only
  PipeWire camera consumers show: Firefox, OBS's "Video Capture (PipeWire)",
  apps using the camera portal. A v4l2loopback device (OBS's virtual
  camera) is a v4l2 node, so its consumers read as camera.
- **The camera and screen split is untested end to end**: this desktop has
  no webcam, and a cast needs the portal's picker. What was verified, with a
  `qs -p` probe loading the real service while a `parec` recorded the mic:
  `Pipewire.linkGroups` lists a group from the mic's ALSA node to the
  stream, `target.id` matches the stream node's `id`, and the first cut of
  `isCamera` called that ALSA node a camera (fixed). Quickshell 0.3.1's
  qmltypes mark `source`/`target` constant.

## False mic positives, fixed 2026-09-28

Every record stream pipewire-pulse creates is `Stream/Input/Audio`, so the
mic lit for pavucontrol's peak meters (one per source *and per sink monitor*
while its window is open), OBS desktop audio, cava and
`parec @DEFAULT_MONITOR@`. Measured with two throwaway `parec`s side by side:
the one on `@DEFAULT_MONITOR@` carries `stream.capture.sink: true`, the one on
`@DEFAULT_SOURCE@` doesn't, and both are otherwise plain
`Stream/Input/Audio`. pipewire-pulse also tags peak-detect streams
`stream.monitor`. Loopback, echo-cancel, filter-chain and combine-stream
capture halves are permanent `Stream/Input/Audio` nodes that carry
`node.link-group`, which app streams don't. All three are skipped now;
verified on the bar: no glyph for the monitor recording, the mic glyph for
the mic one.

## Rejected

- **Polling `pw-dump`** (the old `ScreenShareService` singleton): built on
  the belief that Quickshell could never see a video stream's properties,
  which was the tracking rule misdiagnosed.
- **`PwNodeType.AudioInStream` for the mic**: `PwNodeType` has no video
  counterpart, so the glyphs couldn't share a mechanism; `media.class`
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
- **The scan inline in the module**, on the grounds that only one screen
  listed `privacy`: with `mainScreens` holding DP-1 and eDP-1, a machine
  with both connected ran two trackers over every node (2026-09-28).
- **Telling screen from camera by whether the portal's `Video/Source` node
  exists** (2026-09-28, first cut of the camera glyph): a camera on during a
  cast read as screen; a cast stopped from the portal side left the app's
  stream lingering as a camera; a reload mid-cast could classify the
  consumer before the portal node, flashing camera; and it keyed on
  xdg-desktop-portal-hyprland's node name, so other portals' casts read as
  camera. The note here once said separating them needed a
  `PwNodeLinkTracker` per consumer; `Pipewire.linkGroups` is process-wide,
  so it doesn't.

## Lesson

An empirical "confirmed" finding can still encode the wrong mechanism. The
2026-09-02 synthetic repro did fail, but the write-up blamed the media class
instead of the variable that mattered (tracked vs untracked), because the
untracked case was never isolated as its own test. When retiring a workaround
built on an old finding, re-run the original failure case alongside the fix.
