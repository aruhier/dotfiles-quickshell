# Privacy indicator

## Correction: screen-share detection doesn't need `pw-dump` polling (2026-09-02)

Previous claim (now removed from Known limitations above) was that
Quickshell's `Pipewire` service could never see a screen-share stream:
`PwNode.type` really doesn't classify `Stream/Input/Video` (that part's
still true — `type` stays `Untracked`/`0` for it), but the conclusion drawn
from that — that `properties`/`ready` therefore *never* populate for such a
node — was wrong. The original test only tried a synthetic node with no
`PwObjectTracker` anywhere in the process; **an untracked Pipewire node
never gets its properties bound, full stop, regardless of media class** —
that's the actual rule, and it was misdiagnosed as being about video
streams specifically.

Reconfirmed empirically against a real capture (Firefox sharing a browser
tab via the portal, not a synthetic `gst-launch-1.0` node): a standalone
probe script (`qs -p`) with `PwObjectTracker { objects: Pipewire.nodes.values }`
showed the node's `properties["media.class"]` and `ready` populate and
update live. The same probe with no tracker at all reproduced the original
`ready: false, properties: {}` stuck state on the same live node — so the
fix genuinely is just "track the node", not "impossible via Quickshell".

Found by reading DankMaterialShell's `PrivacyService.qml`
(`AvengeMedia/DankMaterialShell`), which does exactly this — reads
`node.properties["media.class"]` off `Pipewire.nodes.values` directly, no
subprocess. Its `PwObjectTracker` filters to `objects.filter(node =>
!node.isStream)`, which looks like it should exclude a video *stream*
node — but `isStream` turned out to be false for this class of node too
(Quickshell only sets it for media classes it classifies into a real
`PwNodeType`, same root cause as `type` staying `Untracked`), so DMS's
filter includes it anyway. Not obviously robust reasoning to copy blindly,
so this repo just tracks every node instead of relying on that
coincidence.

**Fix:** `services/ScreenShareService.qml` (the `pw-dump`-polling
singleton) is deleted. Screen-share detection now lives inline in
`Privacy.qml` as `screenShareActive`, same shape as the pre-existing
`micActive` — a `PwObjectTracker` over `Pipewire.nodes.values` plus a scan
for `media.class === "Stream/Input/Video"`. (That scan is superseded as of
2026-09-08: the class alone also matches a webcam — see the Privacy.qml
section at the end.) No dedicated service: this
isn't owned subprocess/network I/O (the thing `services/*.qml` exists for
per `notes/layout.md`), just a reactive read of a singleton
Quickshell already keeps process-wide. It also means the tracker only runs
on screens whose layout actually lists `privacy` (DP-1 only, currently) —
same cost-avoidance property every other DP-1-only module gets, which the
old always-on singleton didn't have.

**Lesson:** an empirical "confirmed" finding can still encode the wrong
mechanism. The synthetic repro *did* fail, but the write-up attributed the
failure to the wrong variable (media class) instead of the one that
actually mattered (tracked vs. untracked) because the untracked case was
never isolated as its own test. When retiring a workaround based on an old
finding, re-run the original repro's failure case alongside the fix, not
just the fix in isolation — that's what surfaced the real variable here.


## Privacy.qml: media-class classification, camera vs. screencast (2026-09-08)

Three fixes, each measured against a live graph on this machine (Firefox
sharing a tab via the portal, then a webcam, with Bluetooth buds connected).

**Mic and video both key off `media.class` now**, instead of the mic going
through `PwNodeType.AudioInStream` and the video through a string compare.
`PwNodeType` has no `VideoStream` member, so only one of the two could ever
use it. The case that proves the two forms equivalent is the headset: it
publishes a permanent `bluez_capture_internal` node of class
`Stream/Input/Audio/**Internal**`, which Quickshell types `Untracked` and
which an exact `=== "Stream/Input/Audio"` likewise skips. **Exact compare,
never a prefix** — a prefix match lights the mic icon whenever those buds
are connected, with nothing recording. Noctalia matches exactly too
(`std::ranges::contains` over `kAudioCaptureConsumerClasses`).

**`Stream/Input/Video` alone does not mean screen share** — this corrects
the 2026-09-02 section above, which had screen-share detection as that
media class, full stop. A webcam produces the same class. Measured, the two
are indistinguishable from the consumer side: both are named `firefox` with
no `application.name`, differing only in a Firefox-specific `media.name`
(`webrtc-consume-stream` vs `camera-stream`). So a webcam on a video call
was lighting the screen-share icon.

The discriminator is the producer. The portal publishes its own
`Video/Source` node (`xdg-desktop-portal-hyprland`) that exists only for
the life of a cast — verified by watching it appear and disappear, with a
fresh session id each time (`xdph-streaming-718498`, then `-140892`). The
camera device node (`libcamera_input…`, `media.role: Camera`) is permanent,
so its presence means nothing. `screencastPortalActive` now gates the
screen glyph.

Note the name heuristics DankMaterialShell (`looksLikeScreencast`) and
Noctalia (`kScreenShareNamePrefixes`) both use would fail here: they match
the *capture* node's name, which on this machine says nothing about
screens. Known limit of the portal gate: while a cast and a webcam run at
once, the camera consumer is counted as screen too. Separating them needs a
`PwNodeLinkTracker` per consumer, which this module's scope doesn't justify.

**One app, two names.** Firefox reports `application.name` "Firefox" on its
mic stream and *none at all* on its video one, whose `node.name` is a
lowercase "firefox". The merge key was the raw string, so one app rendered
as two rows — exactly the split that merge exists to prevent. Key is
case-folded now, and the app-reported name wins for display. Measured 2
rows → 1.

**`isStream` bit again.** The 2026-09-02 section already records that
`isStream` is false for a `Stream/Input/Video` node. This pass proposed
narrowing the tracker to `filter(n => n.isStream)` anyway — which would
have dropped the one node the module needs — and only caught it by
re-measuring. Re-read that section before touching the tracker.

