import QtQuick
import Quickshell

// The day and time, or the date while clicked on.
Text {
    id: root

    property bool showDate: false

    text: Qt.formatDateTime(clock.date, showDate ? "d MMMM yyyy" : "dddd HH:mm")
    color: Theme.foreground
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    font.bold: true

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.showDate = !root.showDate
    }
}
