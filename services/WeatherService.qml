pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

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
                return;
            }
            root.fetchForecast();
        });
    }

    Component.onCompleted: refresh()

    // Refresh every 15 minutes.
    property Timer refreshTimer: Timer {
        interval: 900000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
