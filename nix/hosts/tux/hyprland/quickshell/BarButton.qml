import QtQuick

// A Nerd Font glyph in the bar that reacts to clicks and the scroll wheel.
Text {
    id: root

    signal clicked(var mouse)
    signal scrolled(int delta)

    color: Theme.foreground
    font.family: Theme.font
    font.pixelSize: Theme.fontSize + 2

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.clicked(mouse)
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }
}
