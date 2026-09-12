pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.shared
import qs.shared.popup
import "../shared/WeatherIcons.js" as WeatherIcons

// Bar icon and temperature, plus a hover popup with current conditions and
// the hourly/daily forecast. A view over WeatherService, which owns the
// geolocation, the Open-Meteo fetch and the refresh timer.
BarModule {
    id: root

    readonly property var current: WeatherService.current
    readonly property var hourly: WeatherService.hourly
    readonly property var daily: WeatherService.daily
    readonly property bool loading: WeatherService.loading
    readonly property bool errored: WeatherService.errored
    readonly property string locationName: WeatherService.locationName

    readonly property bool hasContent: WeatherService.hasContent

    contentVisible: hasContent
    contentWidth: hasContent ? content.implicitWidth : 0

    // Icon vertical nudge / size bias — see Mpd.qml. Bar glyph only; the
    // popup's forecast icons set their own sizes.
    readonly property real iconVerticalOffset: 0.5
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

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            text: root.current ? WeatherIcons.iconFor(root.current.code, root.current.isDay) : root.errored ? "?" : ""
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.current !== null
            color: Theme.groupText
            text: root.current ? root.displayTemp(root.current.tempC) : ""
        }
    }

    HoverPopupArea {
        loader: popupLoader
        onClicked: WeatherService.refresh()
    }

    // LazyLoader, not Loader — see Clock.qml's popupLoader.
    LazyLoader {
        id: popupLoader
        active: false

        HoverPopup {
            id: popup
            anchorItem: root

            visible: _open && root.hasContent
            onVisibleChanged: {
                if (!visible)
                    popupLoader.active = false;
            }
            implicitWidth: 400
            implicitHeight: body.implicitHeight + 2 * padding

            ColumnLayout {
                id: body
                anchors.fill: parent
                spacing: 10

                // ---- current conditions ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.current !== null

                    Icon {
                        text: root.current ? WeatherIcons.iconFor(root.current.code, root.current.isDay) : ""
                        font.pixelSize: 40
                        color: root.current ? root.tempColor(root.current.tempC) : Theme.textBright
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: root.current ? root.displayTemp(root.current.tempC) : ""
                            font.pixelSize: 26
                            bold: true
                            color: Theme.textBright
                        }
                        StyledText {
                            text: root.current ? WeatherIcons.descriptionFor(root.current.code) : ""
                            font.pixelSize: 12
                            color: Theme.text
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: root.current ? "Feels " + root.displayTemp(root.current.feelsC) : ""
                            font.pixelSize: 12
                            color: Theme.text
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: root.daily.length ? root.displayTemp(root.daily[0].maxC) + " / " + root.displayTemp(root.daily[0].minC) : ""
                            font.pixelSize: 12
                            color: Theme.text
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: root.current ? root.current.humidity + "% hum · " + Math.round(root.current.windKmh) + " km/h" : ""
                            font.pixelSize: 11
                            color: Theme.text
                            opacity: 0.8
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.current === null
                    text: root.loading ? "Fetching weather…" : "Weather unavailable — click to retry"
                    font.pixelSize: 12
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.groupBg
                    visible: root.hourly.length > 0
                }

                // ---- hourly forecast ----
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.hourly.length > 0
                    spacing: 4

                    Repeater {
                        // Gated on popup.visible, not just root.hourly, so
                        // delegates are destroyed while the popup is closed
                        // instead of staying resident for as long as
                        // WeatherService has data — i.e. always.
                        model: popup.visible ? root.hourly : []
                        delegate: ColumnLayout {
                            id: hourCell
                            required property var modelData

                            // maximumWidth must be overridden or fillWidth
                            // does nothing: QtQuick.Layouts clamps a nested
                            // Layout's maximumWidth to its implicitWidth.
                            Layout.fillWidth: true
                            Layout.maximumWidth: Number.POSITIVE_INFINITY
                            spacing: 3
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.formatTime(new Date(hourCell.modelData.time), "HH:mm")
                                font.pixelSize: 10
                                color: Theme.text
                            }
                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                text: WeatherIcons.iconFor(hourCell.modelData.code, hourCell.modelData.isDay)
                                font.pixelSize: 16
                                color: root.tempColor(hourCell.modelData.tempC)
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.displayTemp(hourCell.modelData.tempC)
                                font.pixelSize: 11
                                color: Theme.textBright
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.groupBg
                    visible: root.daily.length > 0
                }

                // ---- daily forecast ----
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.daily.length > 0
                    spacing: 6

                    Repeater {
                        model: popup.visible ? root.daily : []
                        delegate: RowLayout {
                            id: dayRow
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.preferredWidth: 56
                                text: root.dayLabel(dayRow.modelData.date, dayRow.index)
                                font.pixelSize: 12
                                color: Theme.text
                            }
                            Icon {
                                Layout.preferredWidth: 22
                                text: WeatherIcons.iconFor(dayRow.modelData.code, true)
                                font.pixelSize: 15
                                color: root.tempColor((dayRow.modelData.maxC + dayRow.modelData.minC) / 2)
                            }
                            StyledText {
                                Layout.preferredWidth: 36
                                text: dayRow.modelData.pop + "%"
                                font.pixelSize: 11
                                color: Theme.text
                                opacity: 0.8
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: root.displayTemp(dayRow.modelData.minC)
                                font.pixelSize: 12
                                color: Theme.text
                            }
                            StyledText {
                                text: root.displayTemp(dayRow.modelData.maxC)
                                font.pixelSize: 12
                                bold: true
                                color: Theme.textBright
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.groupBg
                    visible: root.daily.length > 0
                }

                // ---- footer ----
                // Not gated on daily.length like the sections above: when the
                // fetch failed before ever succeeding this is the whole popup,
                // and the refresh button is the way out of that state.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        text: root.errored && !root.current ? "Weather unavailable" : (root.locationName || "Current location")
                        font.pixelSize: 10
                        color: Theme.text
                        opacity: 0.7
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: root.daily.length > 0
                        text: WeatherIcons.glyph("sunrise") + " " + (root.daily.length ? Qt.formatTime(new Date(root.daily[0].sunrise), "HH:mm") : "")
                        font.pixelSize: 10
                        color: Theme.text
                        opacity: 0.7
                    }
                    StyledText {
                        visible: root.daily.length > 0
                        text: WeatherIcons.glyph("sunset") + " " + (root.daily.length ? Qt.formatTime(new Date(root.daily[0].sunset), "HH:mm") : "")
                        font.pixelSize: 10
                        color: Theme.text
                        opacity: 0.7
                    }

                    // Spins while a request is in flight. Always completes
                    // the turn it's on rather than stopping dead at whatever
                    // angle the response landed: a fetch usually finishes in
                    // well under one turn, and a click that produced no
                    // visible spin would look like it did nothing again.
                    PressableIcon {
                        id: refreshButton
                        text: WeatherIcons.glyph("refresh")
                        font.pixelSize: 13
                        // Full opacity while loading so the spin reads as
                        // active even with the cursor elsewhere.
                        color: Theme.text
                        opacity: root.loading || hovered ? 1.0 : 0.7
                        interactive: !root.loading
                        onActivated: WeatherService.refresh()

                        NumberAnimation {
                            id: spin
                            target: refreshButton
                            property: "rotation"
                            from: 0
                            to: 360
                            duration: 700
                            onFinished: {
                                if (root.loading)
                                    spin.restart();
                                else
                                    refreshButton.rotation = 0;
                            }
                        }

                        // `loading` can already be true when the popup opens
                        // (bar-icon click, timer), so it's a binding-like
                        // handler plus an initial check, not just onActivated.
                        Connections {
                            target: root
                            function onLoadingChanged() {
                                if (root.loading && !spin.running)
                                    spin.start();
                            }
                        }
                        Component.onCompleted: {
                            if (root.loading)
                                spin.start();
                        }
                    }
                }
            }
        }
    }
}
