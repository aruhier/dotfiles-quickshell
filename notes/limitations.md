# Known limitations

## Known limitations

- **`Privacy.qml`** shows a mic icon and a screen-share icon, both computed
  inline (no dedicated service — see `notes/privacy.md`).
- **`Mpd.qml`** shells out to `mpc` (`mpc idleloop player` for events, `mpc
  status`/`current` on each) since Quickshell has no built-in mpd client; the
  bar's mpd module is not MPRIS-based, unlike the control centre's widget.
- **`Weather.qml`** natively implements the bar icon+temperature and a
  popup with current/hourly/daily forecast.
  `WeatherService` refetches on NetworkManager connectivity changes, which
  is what catches a resume. Deliberate gaps: if NM wasn't running when the
  shell started, Quickshell's `Networking` never retries and stays Unknown
  (timer-only); a link NM keeps up across suspend (e.g. a WireGuard tunnel
  with the default route) may give no edge, so data can be up to 15 min
  plus the suspend length old; a request in flight across the suspend
  delays fresh data by up to ~45s (15s timeout, then the 30s retry).
- **`Tray.qml`'s icon order isn't stable** — nothing sorts tray icons
  without an explicit `order` config, so it's just registration order and
  varies per restart. Not a bug to chase.
- **`Battery.qml`** reads `Quickshell.Services.UPower` inline (no service —
  same reasoning as `Privacy.qml`), and shows a `Tooltip` with upower's
  time-to-empty/full estimate. See `notes/battery.md`.

