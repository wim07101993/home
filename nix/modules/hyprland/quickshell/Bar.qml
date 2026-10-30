import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.background

    IdleInhibitor {
        window: bar
        enabled: Toggles.stayAwake
    }

    Workspaces {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        screen: bar.screen
    }

    Clock {
        id: clock
        anchors.centerIn: parent
    }

    QuickToggles {
        anchors.right: clock.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
    }

    Status {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        bar: bar
    }
}
