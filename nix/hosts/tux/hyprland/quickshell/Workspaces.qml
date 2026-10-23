import QtQuick
import Quickshell
import Quickshell.Hyprland

// Workspaces 1 to 5 always, as on Omarchy, and any other that exists.
Row {
    id: root

    required property ShellScreen screen
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var ids: {
        const ids = new Set([1, 2, 3, 4, 5]);
        for (const workspace of Hyprland.workspaces.values) {
            if (workspace.id > 0)
                ids.add(workspace.id);
        }
        return Array.from(ids).sort((a, b) => a - b);
    }

    spacing: 2

    Repeater {
        model: root.ids

        delegate: Item {
            id: workspace

            required property int modelData
            readonly property bool active: root.monitor?.activeWorkspace?.id === modelData
            readonly property bool occupied: Hyprland.workspaces.values.some(w => w.id === modelData && w.toplevels.values.length > 0)

            width: 24
            height: Theme.barHeight

            Text {
                anchors.centerIn: parent
                text: workspace.modelData
                color: workspace.active ? Theme.accent : workspace.occupied ? Theme.foreground : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: workspace.active
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // With a Lua config, Hyprland takes dispatches as Lua.
                onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspace.modelData} })`)
            }
        }
    }
}
