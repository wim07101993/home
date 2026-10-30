-- By keycode, the number row whatever the layout.
for workspace = 1, 10 do
  local key = "code:" .. (workspace + 9)
  hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(workspace) }))
  hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(workspace) }))
  hl.bind("SUPER + SHIFT + ALT + " .. key, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + CTRL + TAB", hl.dsp.focus({ workspace = "previous" }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Switches the workspace between dwindle and scrolling, until Hyprland restarts.
hl.bind("SUPER + S", function()
  local workspace = hl.get_active_workspace()
  if not workspace then
    return
  end
  local layout = workspace.tiled_layout == "dwindle" and "scrolling" or "dwindle"
  hl.workspace_rule({ workspace = tostring(workspace.id), layout = layout })
  hl.exec_cmd("notify-send 'Workspace layout set to " .. layout .. "'")
end)

-- Monitors.

hl.bind("SUPER + SHIFT + ALT + LEFT", hl.dsp.workspace.move({ monitor = "l" }))
hl.bind("SUPER + SHIFT + ALT + RIGHT", hl.dsp.workspace.move({ monitor = "r" }))
hl.bind("SUPER + SHIFT + ALT + UP", hl.dsp.workspace.move({ monitor = "u" }))
hl.bind("SUPER + SHIFT + ALT + DOWN", hl.dsp.workspace.move({ monitor = "d" }))
hl.bind("CTRL + ALT + TAB", hl.dsp.focus({ monitor = "+1" }))
hl.bind("CTRL + ALT + SHIFT + TAB", hl.dsp.focus({ monitor = "-1" }))
