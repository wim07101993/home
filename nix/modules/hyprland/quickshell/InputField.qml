import QtQuick

// A one-line text box with a placeholder.
FocusScope {
    id: root

    property alias text: input.text
    property string placeholder

    signal accepted

    implicitHeight: 38

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        focus: true
        clip: true
        color: Theme.foreground
        selectionColor: Theme.selection
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 2
        onAccepted: root.accepted()

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: root.placeholder
            color: Theme.dim
            font: input.font
        }
    }
}
