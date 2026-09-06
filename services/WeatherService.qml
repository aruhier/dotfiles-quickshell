pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Shared weather state for the whole process — one geolocation lookup and
// one Open-Meteo fetch cycle instead of one per monitor/Bar. Weather.qml
// just reads these properties and calls fetchForecast(); only this
// singleton owns the XHRs/Timer.
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
        var cur = data.current;
        root.current = {
            tempC: cur.temperature_2m,
            feelsC: cur.apparent_temperature,
            humidity: cur.relative_humidity_2m,
            windKmh: cur.wind_speed_10m,
            code: cur.weather_code,
            isDay: cur.is_day === 1
        };

        var h = data.hourly;
        var nowMs = new Date(cur.time).getTime();
        var startIdx = 0;
        for (var k = 0; k < h.time.length; k++) {
            if (new Date(h.time[k]).getTime() >= nowMs) {
                startIdx = k;
                break;
            }
        }
        var hrs = [];
        for (var i = startIdx; i < Math.min(h.time.length, startIdx + 8); i++) {
            hrs.push({
                time: h.time[i],
                tempC: h.temperature_2m[i],
                pop: h.precipitation_probability[i],
                code: h.weather_code[i],
                isDay: h.is_day[i] === 1
            });
        }
        root.hourly = hrs;

        var d = data.daily;
        var days = [];
        for (var j = 0; j < d.time.length; j++) {
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

    function fetchForecast() {
        if (isNaN(root.latitude) || isNaN(root.longitude)) {
            root.errored = true;
            return;
        }

        root.loading = true;
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude + "&longitude=" + root.longitude + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day" + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset" + "&timezone=auto&forecast_days=7";

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.loading = false;
            try {
                if (xhr.status !== 200)
                    throw new Error("http " + xhr.status);
                root.applyForecast(JSON.parse(xhr.responseText));
                root.errored = false;
                root.lastUpdated = Date.now();
            } catch (e) {
                root.errored = true;
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function resolveLocationAndFetch() {
        var envLat = Quickshell.env("QS_WEATHER_LAT");
        var envLon = Quickshell.env("QS_WEATHER_LON");
        if (envLat && envLon) {
            root.latitude = parseFloat(envLat);
            root.longitude = parseFloat(envLon);
            root.fetchForecast();
            return;
        }

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            try {
                var geo = JSON.parse(xhr.responseText);
                root.latitude = geo.lat;
                root.longitude = geo.lon;
                root.locationName = [geo.city, geo.country].filter(function (s) {
                    return !!s;
                }).join(", ");
            } catch (e) {
            // fall through with NaN coords; fetchForecast() will mark errored
            }
            root.fetchForecast();
        };
        xhr.open("GET", "http://ip-api.com/json/?fields=lat,lon,city,country");
        xhr.send();
    }

    Component.onCompleted: resolveLocationAndFetch()

    property Timer refreshTimer: Timer {
        interval: 900000
        running: true
        repeat: true
        onTriggered: root.fetchForecast()
    }
}
