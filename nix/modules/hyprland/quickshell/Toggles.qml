pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The bar's quick toggles. Each starts off with every login.
Singleton {
    id: root

    // Bar.qml's IdleInhibitor follows this, and hypridle honours inhibitors.
    property bool stayAwake: false

    // Notifications.qml drops all but critical notifications while this is on.
    property bool silent: false

    property bool nightLight: false

    onNightLightChanged: Quickshell.execDetached(nightLight
        ? ["hyprctl", "hyprsunset", "temperature", "4000"]
        : ["hyprctl", "hyprsunset", "identity"])

    // For the keybindings in hyprland.lua.
    IpcHandler {
        target: "toggles"

        function toggleStayAwake(): void {
            root.stayAwake = !root.stayAwake;
        }

        function toggleNightLight(): void {
            root.nightLight = !root.nightLight;
        }

        function toggleSilent(): void {
            root.silent = !root.silent;
        }
    }
}
