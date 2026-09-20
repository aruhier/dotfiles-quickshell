pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.shared
import qs.shared.popup
import qs.themes

// Clock with a hover popup showing a native month-grid calendar.
BarModule {
    id: root

    contentWidth: content.implicitWidth

    // On the minute, since that's the label's resolution; SystemClock aligns
    // its ticks to the boundary itself.
    readonly property date now: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Icon vertical nudge / size bias — see Mpd.qml.
    readonly property real iconVerticalOffset: 1
    readonly property real iconSizeRatio: 1.0

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.iconLabelSpacing

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.iconVerticalOffset
            sizeRatio: root.iconSizeRatio
            color: root.textColor
            text: "󰃭"
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            color: root.textColor
            text: Qt.formatDateTime(root.now, "ddd dd MMM  hh:mm")
        }
    }

    HoverPopupArea {
        loader: popupLoader
    }

    // LazyLoader, not Loader — HoverPopup is a PopupWindow, not an Item. Torn
    // down on close: the grid is ~130 items behind a popup opened a few times
    // a session, and a created popup window holds its GPU context (~3-4MB,
    // never freed) for the life of the process. Costs one frame on reopen.
    LazyLoader {
        id: popupLoader
        active: false

        HoverPopup {
            id: popup
            anchorItem: root

            // The month on display, independent of the live clock.
            property int viewYear: root.now.getFullYear()
            property int viewMonth: root.now.getMonth()

            // Reset on close, not open, so the grid always opens on the
            // current month without racing the same visibleChanged signal.
            // Tearing down here is safe — it fires after HoverPopup's own
            // hideTimer, so nothing still needs the popup.
            onVisibleChanged: {
                if (!visible) {
                    goToday();
                    popupLoader.active = false;
                }
            }

            function goToday() {
                viewYear = root.now.getFullYear();
                viewMonth = root.now.getMonth();
            }

            function shiftMonth(delta) {
                let m = viewMonth + delta;
                let y = viewYear;
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

            // Qt::DayOfWeek (Mon=1..Sun=7) -> JS getDay() (Sun=0..Sat=6), so
            // locale and calendar math share one convention.
            function localeFirstDow() {
                return Qt.locale().firstDayOfWeek % 7;
            }

            function dayHeaders() {
                const first = localeFirstDow();
                const names = [];
                for (let i = 0; i < 7; i++) {
                    const jsDow = (first + i) % 7;
                    const qtDow = jsDow === 0 ? 7 : jsDow;
                    names.push(Qt.locale().dayName(qtDow, Locale.ShortFormat));
                }
                return names;
            }

            // 42 cells (6 weeks), including the leading/trailing days of
            // adjacent months needed to fill a rectangular grid.
            function calendarCells() {
                const first = localeFirstDow();
                const firstOfMonth = new Date(viewYear, viewMonth, 1);
                const leading = (firstOfMonth.getDay() - first + 7) % 7;
                const start = new Date(viewYear, viewMonth, 1 - leading);

                const cells = [];
                for (let i = 0; i < 42; i++) {
                    const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
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

            implicitWidth: body.implicitWidth + 2 * padding
            implicitHeight: body.implicitHeight + 2 * padding

            ColumnLayout {
                id: body
                anchors.fill: parent
                spacing: 10

                // ---- month header + nav ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    PressableIcon {
                        text: "‹"
                        font.pixelSize: 16
                        hitPadding: 6
                        onActivated: popup.shiftMonth(-1)
                    }

                    // Click: back to today.
                    PressableIcon {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDate(new Date(popup.viewYear, popup.viewMonth, 1), "MMMM yyyy")
                        font.pixelSize: 14
                        bold: true
                        color: Theme.textBright
                        onActivated: popup.goToday()
                    }

                    PressableIcon {
                        text: "›"
                        font.pixelSize: 16
                        hitPadding: 6
                        onActivated: popup.shiftMonth(1)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.groupBg
                }

                // ---- day-of-week header ----
                GridLayout {
                    columns: 7
                    rowSpacing: 4
                    columnSpacing: 2

                    Repeater {
                        model: popup.headers
                        delegate: StyledText {
                            id: dayHeader
                            required property string modelData

                            Layout.preferredWidth: 28
                            horizontalAlignment: Text.AlignHCenter
                            text: dayHeader.modelData
                            font.pixelSize: 11
                            opacity: 0.7
                        }
                    }

                    // ---- day grid ----
                    Repeater {
                        model: popup.cells
                        delegate: Rectangle {
                            id: dayCell
                            required property var modelData

                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 24
                            radius: 6
                            color: dayCell.modelData.isToday ? Theme.accent : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: dayCell.modelData.day
                                font.pixelSize: 12
                                color: dayCell.modelData.isToday ? Theme.accentText : (dayCell.modelData.inMonth ? Theme.textBright : Theme.text)
                                opacity: dayCell.modelData.inMonth ? 1.0 : 0.35
                            }
                        }
                    }
                }
            }
        }
    }
}
