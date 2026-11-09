-- Omarchy's keybindings and look on Hyprland 0.55, with the Quickshell config
-- in ./quickshell as bar, launcher and notifications.
--
-- The rest is in ./desktop. Hyprland resolves require() against the directory
-- this file is in, /etc/xdg/hypr, and starts a fresh Lua state on every reload,
-- so edits to the parts are picked up as well.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Qt apps take Plasma's theme here too, and the bar Plasma's icons.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QS_ICON_THEME", "breeze-dark")

hl.on("hyprland.start", function()
  hl.exec_cmd("qs -c desktop")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("hyprsunset")
  hl.exec_cmd("@polkitAgent@")
end)

require("desktop.looknfeel")
require("desktop.input")
require("desktop.windows")

require("desktop.bindings.applications")
require("desktop.bindings.shell")
require("desktop.bindings.clipboard")
require("desktop.bindings.windows")
require("desktop.bindings.workspaces")
require("desktop.bindings.media")
