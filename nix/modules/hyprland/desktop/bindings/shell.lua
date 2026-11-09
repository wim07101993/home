local apps = require("desktop.apps")

local function quickshell(call)
  return hl.dsp.exec_cmd("qs ipc -c desktop call " .. call)
end

hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(apps.launcher))
hl.bind("SUPER + ALT + SPACE", hl.dsp.exec_cmd(apps.launcher))
hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("loginctl lock-session"))

hl.bind("SUPER + CTRL + A", apps.tui("wiremix"))
hl.bind("SUPER + CTRL + B", apps.tui("bluetui"))
hl.bind("SUPER + CTRL + W", apps.tui("nmtui"))
hl.bind("SUPER + CTRL + T", apps.tui("btop"))

hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots"))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd("hyprshot -m window -o ~/Pictures/Screenshots"))
hl.bind("SUPER + PRINT", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"))

hl.bind("SUPER + CTRL + Z", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)
hl.bind("SUPER + CTRL + ALT + Z", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)
