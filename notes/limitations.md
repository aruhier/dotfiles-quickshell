# Known limitations

## Known limitations

- **`Privacy.qml`** shows a mic icon and a screen-share icon, both computed
  inline (no dedicated service — see `notes/privacy.md`).
- **`Mpd.qml`** shells out to `mpc` (`mpc idleloop player` for events, `mpc
  status`/`current` on each) since Quickshell has no built-in mpd client; the
  bar's mpd module is not MPRIS-based, unlike the control centre's widget.
- **`Weather.qml`** natively implements the bar icon+temperature and a
  popup with current/hourly/daily forecast.
- **`Tray.qml`'s icon order isn't stable** — nothing sorts tray icons
  without an explicit `order` config, so it's just registration order and
  varies per restart. Not a bug to chase.
- **`Battery.qml`** reads `Quickshell.Services.UPower` inline (no service —
  same reasoning as `Privacy.qml`), and shows a `Tooltip` with upower's
  time-to-empty/full estimate. See `notes/battery.md`.

