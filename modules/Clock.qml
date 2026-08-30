import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../shared"

// Mirrors waybar's "clock" module (format + tooltip-format), but the
// tooltip-format's {calendar} is reimplemented as a native month-grid popup
// instead of a pango <tt> text block — same information, own visual style.
Item {
    id: root

    required property var theme

    implicitWidth: content.implicitWidth + 12
    implicitHeight: theme.barHeight
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.theme.resizeDuration
            easing.type: root.theme.resizeEasing
        }
    }

    property date now: new Date()

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 1
    readonly property real iconSizeRatio: 1.0

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.iconSize(root.iconSizeRatio)
            color: root.theme.groupText
            text: "󰃭"
        }

        Text {
            id: label
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
            color: root.theme.groupText
            text: Qt.formatDateTime(root.now, "ddd dd MMM  hh:mm")
        }
    }

    // Closes immediately (no grace period) when PopupCoordinator hands
    // ownership to a different module's popup.
    function forceClosePopup() {
        popupHideTimer.stop();
        popup._open = false;
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: {
            if (containsMouse) {
                popupHideTimer.stop();
                PopupCoordinator.activate(root);
                popup._open = true;
            } else {
                popupHideTimer.restart();
            }
        }
    }

    // Grace-period timer so moving the cursor from the module onto the
    // popup (a separate surface a few px away) doesn't close it mid-transit
    // — same pattern as Weather.qml / shared/Tooltip.qml.
    Timer {
        id: popupHideTimer
        interval: 200
        onTriggered: {
            if (!hover.containsMouse && !popupHover.containsMouse) {
                popup._open = false;
                PopupCoordinator.deactivate(root);
            }
        }
    }

    PopupWindow {
        id: popup

        property bool _open: false

        // Month currently displayed, independent of the live clock — reset
        // to the current month each time the popup opens so navigating away
        // never leaves it stranded on an old month next time it's shown.
        property int viewYear: root.now.getFullYear()
        property int viewMonth: root.now.getMonth()

        // Reset on close (not open): 'cells' below depends on viewYear/
        // viewMonth only while visible, so resetting them here — before the
        // next open, rather than racing the same visibleChanged signal that
        // flips 'visible' true — guarantees the grid opens on the current
        // month rather than wherever navigation last left it.
        onVisibleChanged: {
            if (!visible)
                goToday();
        }

        function goToday() {
            viewYear = root.now.getFullYear();
            viewMonth = root.now.getMonth();
        }

        function shiftMonth(delta) {
            var m = viewMonth + delta;
            var y = viewYear;
            while (m < 0) {
                m += 12;
                y -= 1;
            }
            while (m > 11) {
                m -= 12;
                y += 1;
            }
            viewMonth = m;
            viewYear = y;
        }

        // Qt::DayOfWeek (Monday=1 .. Sunday=7) -> JS Date.getDay() convention
        // (Sunday=0 .. Saturday=6), so locale and calendar math share one
        // frame of reference throughout.
        function localeFirstDow() {
            return Qt.locale().firstDayOfWeek % 7;
        }

        function dayHeaders() {
            var first = localeFirstDow();
            var names = [];
            for (var i = 0; i < 7; i++) {
                var jsDow = (first + i) % 7;
                var qtDow = jsDow === 0 ? 7 : jsDow;
                names.push(Qt.locale().dayName(qtDow, Locale.ShortFormat));
            }
            return names;
        }

        // 42 cells (6 weeks) covering the leading/trailing days of adjacent
        // months needed to fill a rectangular grid.
        function calendarCells() {
            var first = localeFirstDow();
            var firstOfMonth = new Date(viewYear, viewMonth, 1);
            var leading = (firstOfMonth.getDay() - first + 7) % 7;
            var start = new Date(viewYear, viewMonth, 1 - leading);

            var cells = [];
            for (var i = 0; i < 42; i++) {
                var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
                cells.push({
                    day: d.getDate(),
                    month: d.getMonth(),
                    year: d.getFullYear(),
                    inMonth: d.getMonth() === viewMonth,
                    isToday: d.getFullYear() === root.now.getFullYear() && d.getMonth() === root.now.getMonth() && d.getDate() === root.now.getDate()
                });
            }
            return cells;
        }

        readonly property var cells: visible ? calendarCells() : []
        readonly property var headers: visible ? dayHeaders() : []

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
        visible: _open
        implicitWidth: body.implicitWidth + 28
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
                        PopupCoordinator.activate(root);
                        popup._open = true;
                    } else {
                        popupHideTimer.restart();
                    }
                }
            }

            ColumnLayout {
                id: body
                anchors.centerIn: parent
                spacing: 10

                // ---- month header + nav ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        renderType: Text.NativeRendering
                        text: "‹"
                        font.pixelSize: 16
                        color: root.theme.text
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.shiftMonth(-1)
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDate(new Date(popup.viewYear, popup.viewMonth, 1), "MMMM yyyy")
                        font.pixelSize: 14
                        font.bold: true
                        color: root.theme.textBright
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.goToday()
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: "›"
                        font.pixelSize: 16
                        color: root.theme.text
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.shiftMonth(1)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.theme.groupBg
                }

                // ---- day-of-week header ----
                GridLayout {
                    columns: 7
                    rowSpacing: 4
                    columnSpacing: 2

                    Repeater {
                        model: popup.headers
                        delegate: Text {
                            renderType: Text.NativeRendering
                            Layout.preferredWidth: 28
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font.pixelSize: 11
                            color: root.theme.text
                            opacity: 0.7
                        }
                    }

                    // ---- day grid ----
                    Repeater {
                        model: popup.cells
                        delegate: Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 24
                            radius: 6
                            color: modelData.isToday ? root.theme.accent : "transparent"

                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: modelData.day
                                font.pixelSize: 12
                                color: modelData.isToday ? root.theme.accentText : (modelData.inMonth ? root.theme.textBright : root.theme.text)
                                opacity: modelData.inMonth ? 1.0 : 0.35
                            }
                        }
                    }
                }
            }
        }
    }
}
