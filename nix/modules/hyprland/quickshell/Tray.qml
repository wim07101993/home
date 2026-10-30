import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// Status icons of running apps. Left click activates, right click opens the
// app's menu.
Row {
    id: root

    required property var bar

    spacing: 10

    Repeater {
        model: SystemTray.items

        delegate: IconImage {
            id: icon

            required property SystemTrayItem modelData

            implicitSize: 16
            source: modelData.icon

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton && !icon.modelData.onlyMenu) {
                        icon.modelData.activate();
                    } else if (icon.modelData.hasMenu) {
                        const position = icon.mapToItem(root.bar.contentItem, 0, icon.height + 6);
                        icon.modelData.display(root.bar, position.x, position.y);
                    }
                }
            }
        }
    }
}
