import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../services"
import "../shared/WeatherIcons.js" as WeatherIcons

// A native quickshell weather widget: renders a bar icon+temperature and its
// own popup (current + hourly/daily forecast) instead of a monospace pango
// tooltip. The actual Open-Meteo fetch/geolocation/refresh-timer lives in
// services/WeatherService.qml (a singleton) so there's exactly one fetch cycle
// for the whole qs process, not one per monitor/Bar — this is just a view
// over that shared state.
Item {
    id: root

    required property var theme

    readonly property var current: WeatherService.current
    readonly property var hourly: WeatherService.hourly
    readonly property var daily: WeatherService.daily
    readonly property bool loading: WeatherService.loading
    readonly property bool errored: WeatherService.errored
    readonly property string locationName: WeatherService.locationName

    readonly property bool hasContent: WeatherService.hasContent

    implicitWidth: hasContent ? content.implicitWidth + 12 : 0
    implicitHeight: theme.barHeight
    // Smooth resize — see Theme.qml's resizeDuration. Also covers the
    // initial 0 -> real-width grow once the first forecast arrives.
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
        }
    }

    // Nudges the compact bar icon down from its box-center — see Mpd.qml's
    // iconVerticalOffset for why. Tuned per module.
    readonly property real iconVerticalOffset: 0.5

    // Bias against the shared iconFontSize — see Theme.qml's iconSize().
    // 1.0 = no change; no bias needed here. (Only the bar glyph uses this —
    // the popup's forecast icons below use their own hardcoded sizes, not
    // theme.iconFontSize.)
    readonly property real iconSizeRatio: 0.9

    function displayTemp(c) {
        return Math.round(c) + "°C";
    }

    // Blue -> green -> amber -> red gradient.
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

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            renderType: Text.NativeRendering
            // Box-centered against the Row, not baseline — see Mpd.qml.
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.iconSize(root.iconSizeRatio)
            color: root.theme.groupText
            text: root.current ? WeatherIcons.iconFor(root.current.code, root.current.isDay) : root.errored ? "?" : ""
        }

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            visible: root.current !== null
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
            color: root.theme.groupText
            text: root.current ? root.displayTemp(root.current.tempC) : ""
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: WeatherService.fetchForecast()
        onContainsMouseChanged: {
            if (containsMouse) {
                popupHideTimer.stop();
                popup._open = true;
            } else {
                popupHideTimer.restart();
            }
        }
    }

    Timer {
        id: popupHideTimer
        interval: 200
        onTriggered: {
            if (!hover.containsMouse && !popupHover.containsMouse)
                popup._open = false;
        }
    }

    PopupWindow {
        id: popup

        // See shared/Tooltip.qml for why this needs a grace-period timer
        // rather than a plain `hover.containsMouse || popupHover.containsMouse`
        // OR: the module and the popup are separate surfaces 4px apart (see
        // onAnchoring below), so the instant the cursor leaves the module,
        // a non-debounced OR would unmap the popup before the cursor ever
        // reaches it.
        property bool _open: false

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
        visible: _open && root.hasContent
        implicitWidth: 400
        implicitHeight: body.implicitHeight + 28

        Rectangle {
            anchors.fill: parent
            color: "#1e1e1e"
            border.color: root.theme.accent
            border.width: 1
            radius: 10

            MouseArea {
                id: popupHover
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: {
                    if (containsMouse) {
                        popupHideTimer.stop();
                        popup._open = true;
                    } else {
                        popupHideTimer.restart();
                    }
                }
            }

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
                        renderType: Text.NativeRendering
                        text: root.current ? WeatherIcons.iconFor(root.current.code, root.current.isDay) : ""
                        font.family: root.theme.fontFamily
                        font.pixelSize: 40
                        color: root.current ? root.tempColor(root.current.tempC) : root.theme.textBright
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            renderType: Text.NativeRendering
                            text: root.current ? root.displayTemp(root.current.tempC) : ""
                            font.pixelSize: 26
                            font.bold: true
                            color: root.theme.textBright
                        }
                        Text {
                            renderType: Text.NativeRendering
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
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignRight
                            text: root.current ? "Feels " + root.displayTemp(root.current.feelsC) : ""
                            font.pixelSize: 12
                            color: root.theme.text
                        }
                        Text {
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignRight
                            text: root.daily.length ? root.displayTemp(root.daily[0].maxC) + " / " + root.displayTemp(root.daily[0].minC) : ""
                            font.pixelSize: 12
                            color: root.theme.text
                        }
                        Text {
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignRight
                            text: root.current ? root.current.humidity + "% hum · " + Math.round(root.current.windKmh) + " km/h" : ""
                            font.pixelSize: 11
                            color: root.theme.text
                            opacity: 0.8
                        }
                    }
                }

                Text {
                    renderType: Text.NativeRendering
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
                            // fillWidth alone doesn't let this column grow:
                            // QtQuick.Layouts auto-binds a nested Layout's
                            // (this ColumnLayout's) maximumWidth to its own
                            // implicitWidth by default, clamping it right
                            // back to its natural content size regardless of
                            // fillWidth — see AGENT.md for how this was
                            // diagnosed. minimumWidth/preferredWidth don't
                            // need the same override: they only affect the
                            // exact per-column split of the extra space, not
                            // whether the row reaches full width at all.
                            Layout.fillWidth: true
                            Layout.maximumWidth: Number.POSITIVE_INFINITY
                            spacing: 3
                            Text {
                                renderType: Text.NativeRendering
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.formatTime(new Date(modelData.time), "HH:mm")
                                font.pixelSize: 10
                                color: root.theme.text
                            }
                            Text {
                                renderType: Text.NativeRendering
                                Layout.alignment: Qt.AlignHCenter
                                text: WeatherIcons.iconFor(modelData.code, modelData.isDay)
                                font.family: root.theme.fontFamily
                                font.pixelSize: 16
                                color: root.tempColor(modelData.tempC)
                            }
                            Text {
                                renderType: Text.NativeRendering
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
                                renderType: Text.NativeRendering
                                Layout.preferredWidth: 56
                                text: root.dayLabel(modelData.date, index)
                                font.pixelSize: 12
                                color: root.theme.text
                            }
                            Text {
                                renderType: Text.NativeRendering
                                Layout.preferredWidth: 22
                                text: WeatherIcons.iconFor(modelData.code, true)
                                font.family: root.theme.fontFamily
                                font.pixelSize: 15
                                color: root.tempColor((modelData.maxC + modelData.minC) / 2)
                            }
                            Text {
                                renderType: Text.NativeRendering
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
                                renderType: Text.NativeRendering
                                text: root.displayTemp(modelData.minC)
                                font.pixelSize: 12
                                color: root.theme.text
                            }
                            Text {
                                renderType: Text.NativeRendering
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
                        renderType: Text.NativeRendering
                        text: root.locationName || "Current location"
                        font.pixelSize: 10
                        color: root.theme.text
                        opacity: 0.7
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        renderType: Text.NativeRendering
                        visible: root.daily.length > 0
                        text: WeatherIcons.glyph("sunrise") + " " + (root.daily.length ? Qt.formatTime(new Date(root.daily[0].sunrise), "HH:mm") : "")
                        font.family: root.theme.fontFamily
                        font.pixelSize: 10
                        color: root.theme.text
                        opacity: 0.7
                    }
                    Text {
                        renderType: Text.NativeRendering
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
