pragma Singleton

import QtQuick
import Quickshell

// Catppuccin Mocha and the font of the Omarchy theme on the desktop.
Singleton {
    readonly property color background: "#1e1e2e"
    readonly property color surface: "#313244"
    readonly property color selection: "#45475a"
    readonly property color foreground: "#cdd6f4"
    readonly property color dim: "#6c7086"
    readonly property color accent: "#89b4fa"
    readonly property color red: "#f38ba8"
    readonly property color green: "#a6e3a1"

    readonly property string font: "CaskaydiaMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int barHeight: 26
}
