# Known limitations

## Known limitations

- **`Privacy.qml`** shows mic, screen-share and camera icons, a thin view
  over `PrivacyService` — see `notes/privacy.md` for its known limits.
- **`Mpd.qml`** shells out to `mpc` (`mpc idleloop player` for events, `mpc
  status`/`current` on each) since Quickshell has no built-in mpd client; the
  bar's mpd module is not MPRIS-based, unlike the control centre's widget.
  `MpdService` never restarts a read in flight: `running = false` kills it,
  its partial stdout still reaches the collector, and an `mpc status` cut off
  before its `volume:` line read as "disconnected" — the module collapsed and
  re-expanded whenever idleloop emitted two lines close together (a state
  change and a seek). Hence the dirty flag and re-run on exit. Tags fall back
  in the `mpc current` format (`[%artist%|%name%]`, `[%title%|%file%]`), since
  a missing one expands to "" and a web stream has no artist. idleloop's
  retry is keyed on `running`, not `exited`: a Quickshell `Process` that
  fails to start (mpc missing) only emits `runningChanged` (process.cpp,
  0.3.1), so an `onExited` retry died for good.
- **`Weather.qml`** natively implements the bar icon+temperature and a
  popup with current/hourly/daily forecast.
  `WeatherService` refetches on NetworkManager connectivity changes, which
  is what catches a resume. Deliberate gaps: if NM wasn't running when the
  shell started, Quickshell's `Networking` never retries and stays Unknown
  (timer-only); a link NM keeps up across suspend (e.g. a WireGuard tunnel
  with the default route) may give no edge, so data can be up to 15 min
  plus the suspend length old; a request in flight across the suspend
  delays fresh data by up to ~45s (15s timeout, then the 30s retry); a
  link that returns while a request is in flight clears the backoff, so
  that request's failure retries after 30s rather than a long backoff.
  Location comes from `QS_WEATHER_LAT`/`QS_WEATHER_LON` when both parse as
  numbers (the footer then reads "Current location", there being no name),
  else from ip-api over plain http. It is looked up again, and the forecast
  refetched, whenever NM's connectivity comes back from None (travel, a
  resume) and on every manual refresh (a click on the module or the
  popup's refresh button); a failed re-lookup keeps the old coordinates and retries next
  cycle. A network change NM never reports as None (e.g. a VPN hop) doesn't
  trigger it. Stale data is deliberately not dimmed. Units are fixed metric
  (°C, km/h).
- **`Clock.qml`'s calendar starts on the locale's first day of the week**,
  and the quickshell process may not get the session's `LC_TIME`: here it ran
  with only `LANG=en_US.UTF-8` while the terminal had `LC_TIME=en_GB.UTF-8`,
  so the grid started on Sunday. `firstDayOfWeek` at the top of the file
  pins it, to `Qt.Monday`; `Qt.locale().firstDayOfWeek` there would follow
  the locale again, once the service gets `LC_TIME`.
- **`Tray.qml`'s icon order isn't stable** — nothing sorts tray icons
  without an explicit `order` config, so it's just registration order and
  varies per restart. Not a bug to chase.
- **`Battery.qml`** reads `Quickshell.Services.UPower` inline (no service:
  UPower is already a process-wide singleton, and nothing here needs a
  tracker), and shows a `Tooltip` with upower's
  time-to-empty/full estimate. See `notes/battery.md`.

