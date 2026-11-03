import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland

// Notification popups under the bar's right end. A left click runs the
// notification's default action, any click dismisses it.
Scope {
    id: root

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        imageSupported: true

        onNotification: notification => {
            if (!Toggles.silent || notification.urgency === NotificationUrgency.Critical)
                notification.tracked = true;
        }
    }

    IpcHandler {
        target: "notifications"

        function dismissNewest(): void {
            const notifications = server.trackedNotifications.values;
            if (notifications.length > 0)
                notifications[notifications.length - 1].dismiss();
        }

        function dismissAll(): void {
            for (const notification of server.trackedNotifications.values.slice())
                notification.dismiss();
        }
    }

    PanelWindow {
        visible: server.trackedNotifications.values.length > 0

        anchors {
            top: true
            right: true
        }
        margins {
            top: 8
            right: 8
        }
        implicitWidth: 380
        implicitHeight: popups.implicitHeight
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"

        Column {
            id: popups

            width: parent.width
            spacing: 8

            Repeater {
                model: server.trackedNotifications

                delegate: Rectangle {
                    id: popup

                    required property Notification modelData

                    width: popups.width
                    height: content.implicitHeight + 24
                    color: Theme.background
                    border.color: modelData.urgency === NotificationUrgency.Critical ? Theme.red : Theme.accent
                    border.width: 2

                    Column {
                        id: content

                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 4

                        Text {
                            width: parent.width
                            text: popup.modelData.summary
                            color: Theme.foreground
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: popup.modelData.body
                            color: Theme.foreground
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }
                    }

                    // Critical ones stay until dismissed. The cap keeps a
                    // misreported timeout from pinning a popup.
                    Timer {
                        running: popup.modelData.urgency !== NotificationUrgency.Critical
                        interval: popup.modelData.expireTimeout > 0 ? Math.min(popup.modelData.expireTimeout, 10000) : 5000
                        onTriggered: popup.modelData.expire()
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                for (const action of popup.modelData.actions) {
                                    if (action.identifier === "default")
                                        action.invoke();
                                }
                            }
                            popup.modelData.dismiss();
                        }
                    }
                }
            }
        }
    }
}
