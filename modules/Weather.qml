import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../shared/WeatherIcons.js" as WeatherIcons

// A native quickshell weather widget: fetches current conditions + hourly/
// daily forecast straight from Open-Meteo (no external script), and renders
// its own popup instead of a monospace pango tooltip. Location is detected
// once via IP geolocation, or pinned with QS_WEATHER_LAT/QS_WEATHER_LON.
Item {
    id: root

    required property var theme

    property real latitude: NaN
    property real longitude: NaN
    property string locationName: ""

    property bool useFahrenheit: false

    property var current: null
    property var hourly: []
    property var daily: []
    property bool loading: false
    property bool errored: false
    property double lastUpdated: 0

    readonly property bool hasContent: current !== null || errored

    implicitWidth: hasContent ? label.implicitWidth + 12 : 0
    implicitHeight: theme.barHeight

    function c2f(c) {
        return c * 9 / 5 + 32;
    }

    function displayTemp(c) {
        var v = root.useFahrenheit ? root.c2f(c) : c;
        return Math.round(v) + "°" + (root.useFahrenheit ? "F" : "C");
    }

    // Blue -> green -> amber -> red gradient, graded in Celsius regardless
    // of the unit currently displayed.
    function tempColor(c) {
        if (c < 0)
            return "#6DCEEB";
        if (c < 10)
            return "#8FD6C8";
        if (c < 18)
            return "#9BD68A";
        if (c < 24)
            return "#E3D06B";
        if (c < 30)
            return "#F0A860";
        return "#F0705E";
    }

    function dayLabel(dateStr, index) {
        if (index === 0)
            return "Today";
        return Qt.formatDate(new Date(dateStr + "T00:00:00"), "ddd");
    }

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

    Timer {
        interval: 900000
        running: true
        repeat: true
        onTriggered: root.fetchForecast()
    }

    Text {
        id: label
        anchors.centerIn: parent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
        color: root.theme.groupText
        text: {
            if (root.current)
                return WeatherIcons.iconFor(root.current.code, root.current.isDay) + " " + root.displayTemp(root.current.tempC);
            if (root.errored)
                return "?";
            return "";
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.useFahrenheit = !root.useFahrenheit;
            else
                root.fetchForecast();
        }
    }

    PopupWindow {
        id: popup

        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.Slide
            gravity: Edges.Bottom | Edges.Right
            edges: Edges.Bottom | Edges.Left

            onAnchoring: {
                const pos = root.QsWindow.contentItem.mapFromItem(root, 0, root.height + 4);
                anchor.rect.x = pos.x;
                anchor.rect.y = pos.y;
            }
        }

        color: "transparent"
        visible: hover.containsMouse && root.hasContent
        implicitWidth: 400
        implicitHeight: body.implicitHeight + 28

        Rectangle {
            anchors.fill: parent
            color: "#1e1e1e"
            border.color: root.theme.accent
            border.width: 1
            radius: 10

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ---- current conditions ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.current !== null

                    Text {
                        text: root.current ? WeatherIcons.iconFor(root.current.code, root.current.isDay) : ""
                        font.family: root.theme.fontFamily
                        font.pixelSize: 40
                        color: root.current ? root.tempColor(root.current.tempC) : root.theme.textBright
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: root.current ? root.displayTemp(root.current.tempC) : ""
                            font.pixelSize: 26
                            font.bold: true
                            color: root.theme.textBright
                        }
                        Text {
                            text: root.current ? WeatherIcons.descriptionFor(root.current.code) : ""
                            font.pixelSize: 12
                            color: root.theme.text
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: root.current ? "Feels " + root.displayTemp(root.current.feelsC) : ""
                            font.pixelSize: 12
                            color: root.theme.text
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: root.daily.length ? root.displayTemp(root.daily[0].maxC) + " / " + root.displayTemp(root.daily[0].minC) : ""
                            font.pixelSize: 12
                            color: root.theme.text
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: root.current ? root.current.humidity + "% hum · " + Math.round(root.current.windKmh) + " km/h" : ""
                            font.pixelSize: 11
                            color: root.theme.text
                            opacity: 0.8
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.current === null
                    text: root.loading ? "Fetching weather…" : "Weather unavailable — click to retry"
                    font.pixelSize: 12
                    color: root.theme.text
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.theme.groupBg
                    visible: root.hourly.length > 0
                }

                // ---- hourly forecast ----
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.hourly.length > 0
                    spacing: 4

                    Repeater {
                        model: root.hourly
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.formatTime(new Date(modelData.time), "HH:mm")
                                font.pixelSize: 10
                                color: root.theme.text
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: WeatherIcons.iconFor(modelData.code, modelData.isDay)
                                font.family: root.theme.fontFamily
                                font.pixelSize: 16
                                color: root.tempColor(modelData.tempC)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.displayTemp(modelData.tempC)
                                font.pixelSize: 11
                                color: root.theme.textBright
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.theme.groupBg
                    visible: root.daily.length > 0
                }

                // ---- daily forecast ----
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.daily.length > 0
                    spacing: 6

                    Repeater {
                        model: root.daily
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.preferredWidth: 56
                                text: root.dayLabel(modelData.date, index)
                                font.pixelSize: 12
                                color: root.theme.text
                            }
                            Text {
                                Layout.preferredWidth: 22
                                text: WeatherIcons.iconFor(modelData.code, true)
                                font.family: root.theme.fontFamily
                                font.pixelSize: 15
                                color: root.tempColor((modelData.maxC + modelData.minC) / 2)
                            }
                            Text {
                                Layout.preferredWidth: 36
                                text: modelData.pop + "%"
                                font.pixelSize: 11
                                color: root.theme.text
                                opacity: 0.8
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                text: root.displayTemp(modelData.minC)
                                font.pixelSize: 12
                                color: root.theme.text
                            }
                            Text {
                                text: root.displayTemp(modelData.maxC)
                                font.pixelSize: 12
                                font.bold: true
                                color: root.theme.textBright
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.theme.groupBg
                    visible: root.daily.length > 0
                }

                // ---- footer ----
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.daily.length > 0
                    spacing: 10

                    Text {
                        text: root.locationName || "Current location"
                        font.pixelSize: 10
                        color: root.theme.text
                        opacity: 0.7
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: root.daily.length > 0
                        text: WeatherIcons.glyph("sunrise") + " " + (root.daily.length ? Qt.formatTime(new Date(root.daily[0].sunrise), "HH:mm") : "")
                        font.family: root.theme.fontFamily
                        font.pixelSize: 10
                        color: root.theme.text
                        opacity: 0.7
                    }
                    Text {
                        visible: root.daily.length > 0
                        text: WeatherIcons.glyph("sunset") + " " + (root.daily.length ? Qt.formatTime(new Date(root.daily[0].sunset), "HH:mm") : "")
                        font.family: root.theme.fontFamily
                        font.pixelSize: 10
                        color: root.theme.text
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
