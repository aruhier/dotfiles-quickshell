pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Networking

// Shared weather state: one geolocation lookup and one Open-Meteo fetch cycle
// for the whole process, rather than one per bar. Weather.qml just reads these
// properties and calls refresh().
QtObject {
    id: root

    property real latitude: NaN
    property real longitude: NaN
    property string locationName: ""

    property var current: null
    property var hourly: []
    property var daily: []
    property bool loading: false
    property bool errored: false
    property double lastUpdated: 0

    readonly property bool hasContent: current !== null || errored

    function applyForecast(data) {
        const cur = data.current;
        root.current = {
            tempC: cur.temperature_2m,
            feelsC: cur.apparent_temperature,
            humidity: cur.relative_humidity_2m,
            windKmh: cur.wind_speed_10m,
            code: cur.weather_code,
            isDay: cur.is_day === 1
        };

        const h = data.hourly;
        const nowMs = new Date(cur.time).getTime();
        let startIdx = 0;
        for (let k = 0; k < h.time.length; k++) {
            if (new Date(h.time[k]).getTime() >= nowMs) {
                startIdx = k;
                break;
            }
        }
        const hrs = [];
        for (let i = startIdx; i < Math.min(h.time.length, startIdx + 8); i++) {
            hrs.push({
                time: h.time[i],
                tempC: h.temperature_2m[i],
                pop: h.precipitation_probability[i],
                code: h.weather_code[i],
                isDay: h.is_day[i] === 1
            });
        }
        root.hourly = hrs;

        const d = data.daily;
        const days = [];
        for (let j = 0; j < d.time.length; j++) {
            days.push({
                date: d.time[j],
                code: d.weather_code[j],
                maxC: d.temperature_2m_max[j],
                minC: d.temperature_2m_min[j],
                pop: d.precipitation_probability_max[j],
                sunrise: d.sunrise[j],
                sunset: d.sunset[j]
            });
        }
        root.daily = days;
    }

    // Retries geolocation, not just the forecast: if the startup lookup failed
    // (no network yet) the coordinates stay NaN, and fetching alone would
    // re-flag the error forever.
    function refresh() {
        if (root.loading)
            return;
        if (isNaN(root.latitude) || isNaN(root.longitude))
            root.resolveLocationAndFetch();
        else
            root.fetchForecast();
    }

    // The request in flight, and the timer that gives up on it. QML's
    // XMLHttpRequest has no `timeout` (checked: undefined on Qt 6.11), and a
    // socket stalled by a suspend or a captive portal never reaches DONE on
    // its own — which left `loading` true for the life of the process, so
    // refresh() returned early forever and the popup's spin never stopped.
    // `abort()` completes the request as DONE with status 0, so it takes the
    // ordinary error path below and the next refresh() retries.
    property var xhr: null
    readonly property Timer requestTimeout: Timer {
        interval: 15000
        onTriggered: root.xhr?.abort()
    }

    function request(url, onDone) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.requestTimeout.stop();
            root.xhr = null;
            root.loading = false;
            onDone(xhr);
        };
        root.xhr = xhr;
        root.loading = true;
        root.requestTimeout.restart();
        xhr.open("GET", url);
        xhr.send();
    }

    function fetchForecast() {
        if (isNaN(root.latitude) || isNaN(root.longitude)) {
            root.errored = true;
            root.scheduleNext();
            return;
        }

        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude + "&longitude=" + root.longitude + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day" + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset" + "&timezone=auto&forecast_days=7";

        root.request(url, xhr => {
            try {
                if (xhr.status !== 200)
                    throw new Error("http " + xhr.status);
                root.applyForecast(JSON.parse(xhr.responseText));
                root.errored = false;
                root.lastUpdated = Date.now();
            } catch (e) {
                root.errored = true;
            }
            root.scheduleNext();
        });
    }

    // Coordinates come from QS_WEATHER_LAT/QS_WEATHER_LON if set, otherwise
    // from an IP geolocation lookup.
    function resolveLocationAndFetch() {
        const envLat = Quickshell.env("QS_WEATHER_LAT");
        const envLon = Quickshell.env("QS_WEATHER_LON");
        if (envLat && envLon) {
            root.latitude = parseFloat(envLat);
            root.longitude = parseFloat(envLon);
            root.fetchForecast();
            return;
        }

        root.request("http://ip-api.com/json/?fields=lat,lon,city,country", xhr => {
            try {
                if (xhr.status !== 200)
                    throw new Error("http " + xhr.status);
                const geo = JSON.parse(xhr.responseText);
                if (typeof geo.lat !== "number" || typeof geo.lon !== "number")
                    throw new Error("no coordinates");
                root.latitude = geo.lat;
                root.longitude = geo.lon;
                root.locationName = [geo.city, geo.country].filter(function (s) {
                    return !!s;
                }).join(", ");
            } catch (e) {
                // Coords stay NaN; the next refresh() retries the lookup.
                root.errored = true;
                root.scheduleNext();
                return;
            }
            root.fetchForecast();
        });
    }

    Component.onCompleted: refresh()

    // One timer for both the regular cycle and retries, rescheduled at the end
    // of every cycle so a recovery or a manual refresh puts the next fetch a
    // full interval out. A failure retries after 30s, doubling up to the
    // regular 15 minutes. A successful geolocation doesn't end a cycle: the
    // forecast fetch it chains into does.
    readonly property int refreshInterval: 900000
    readonly property int retryInterval: 30000
    property int failures: 0

    readonly property Timer nextFetch: Timer {
        onTriggered: root.refresh()
    }

    function scheduleNext() {
        root.failures = root.errored ? root.failures + 1 : 0;
        // No point retrying while NetworkManager reports no network at all;
        // onConnectivityChanged resumes when that changes.
        if (root.errored && root.connectivity === NetworkConnectivity.None) {
            root.nextFetch.stop();
            return;
        }
        root.nextFetch.interval = root.errored ? Math.min(root.retryInterval * 2 ** (root.failures - 1), root.refreshInterval) : root.refreshInterval;
        root.nextFetch.restart();
    }

    // Only None pauses retries: NM's Portal and Limited can be false alarms
    // (a DNS blocker's page, an unreachable check URL), and the requests here
    // are tiny. Unknown is every startup until NM answers, or no NM at all.
    readonly property int connectivity: Networking.connectivity

    // Suspend stops the monotonic clock nextFetch runs on, and a dropped link
    // leaves the data errored. On any change, refetch if the data is errored
    // or stale by the wall clock, else re-arm for the wall-clock remainder.
    // Reads `connectivity` itself: bindings on it haven't updated yet here.
    onConnectivityChanged: {
        if (root.connectivity === NetworkConnectivity.None || root.loading)
            return;
        const age = Date.now() - root.lastUpdated;
        if (root.errored || age >= root.refreshInterval) {
            root.failures = 0;
            root.refresh();
        } else {
            root.nextFetch.interval = root.refreshInterval - age;
            root.nextFetch.restart();
        }
    }
}
