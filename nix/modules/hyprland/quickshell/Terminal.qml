pragma Singleton

import Quickshell

Singleton {
    // In a floating window: hyprland.lua floats the TUI.float class.
    function run(command) {
        Quickshell.execDetached(["alacritty", "--class", "TUI.float", "-e"].concat(command));
    }
}
