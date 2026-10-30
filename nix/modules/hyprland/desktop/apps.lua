-- The programs the bindings open.

local apps = {
  terminal = "alacritty",
  browser = "firefox",
  file_manager = "dolphin",
  launcher = "qs ipc -c desktop call launcher toggle",
}

-- A terminal UI in a window of its own, floated by desktop/windows.lua like the
-- ones behind the bar's icons.
function apps.tui(command)
  return hl.dsp.exec_cmd(apps.terminal .. " --class TUI.float -e " .. command)
end

return apps
