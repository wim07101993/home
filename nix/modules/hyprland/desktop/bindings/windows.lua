hl.bind("SUPER + W", hl.dsp.window.close())
hl.bind("SUPER + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- Fullscreen as far as the app knows, while it stays tiled.
hl.bind("SUPER + CTRL + F", function()
  local window = hl.get_active_window()
  if window then
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = window.fullscreen_client == 2 and 0 or 2 }))
  end
end)

-- Pops the window out: floating, 1300x900, centred and on every workspace. And
-- back in again.
hl.bind("SUPER + O", function()
  local window = hl.get_active_window()
  if not window then
    return
  end
  if window.pinned then
    hl.dispatch(hl.dsp.window.pin())
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  else
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.resize({ x = 1300, y = 900 }))
    hl.dispatch(hl.dsp.window.center())
    hl.dispatch(hl.dsp.window.pin())
  end
end)

-- Vim keys as well as the arrows. On a scrolling workspace a width belongs to
-- the column, so a sideways swap moves the whole column to keep each window's
-- width with it.
local function swap_sideways(direction)
  return function()
    local workspace = hl.get_active_workspace()
    if workspace and workspace.tiled_layout == "scrolling" then
      hl.dispatch(hl.dsp.layout("swapcol " .. direction))
    else
      hl.dispatch(hl.dsp.window.swap({ direction = direction }))
    end
  end
end

for _, keys in ipairs({ { "H", "LEFT", "l" }, { "J", "DOWN", "d" }, { "K", "UP", "u" }, { "L", "RIGHT", "r" } }) do
  local vim, arrow, direction = keys[1], keys[2], keys[3]
  local swap = (direction == "l" or direction == "r") and swap_sideways(direction) or hl.dsp.window.swap({ direction = direction })
  hl.bind("SUPER + " .. vim, hl.dsp.focus({ direction = direction }))
  hl.bind("SUPER + " .. arrow, hl.dsp.focus({ direction = direction }))
  hl.bind("SUPER + SHIFT + " .. vim, swap)
  hl.bind("SUPER + SHIFT + " .. arrow, swap)
end

hl.bind("ALT + TAB", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))
hl.bind("ALT + TAB", hl.dsp.window.bring_to_top())
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.bring_to_top())

-- The - and = keys: 100 pixels, 25 with ALT, 300 with CTRL.
for _, step in ipairs({ { "", 100 }, { "ALT + ", 25 }, { "CTRL + ", 300 } }) do
  local mods, px = step[1], step[2]
  hl.bind("SUPER + " .. mods .. "code:20", hl.dsp.window.resize({ x = -px, y = 0, relative = true }))
  hl.bind("SUPER + " .. mods .. "code:21", hl.dsp.window.resize({ x = px, y = 0, relative = true }))
  hl.bind("SUPER + SHIFT + " .. mods .. "code:20", hl.dsp.window.resize({ x = 0, y = -px, relative = true }))
  hl.bind("SUPER + SHIFT + " .. mods .. "code:21", hl.dsp.window.resize({ x = 0, y = px, relative = true }))
end

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Groups.

hl.bind("SUPER + G", hl.dsp.group.toggle())
hl.bind("SUPER + ALT + LEFT", hl.dsp.window.move({ into_group = "l" }))
hl.bind("SUPER + ALT + RIGHT", hl.dsp.window.move({ into_group = "r" }))
hl.bind("SUPER + ALT + UP", hl.dsp.window.move({ into_group = "u" }))
hl.bind("SUPER + ALT + DOWN", hl.dsp.window.move({ into_group = "d" }))
hl.bind("SUPER + ALT + TAB", hl.dsp.group.next())
hl.bind("SUPER + ALT + SHIFT + TAB", hl.dsp.group.prev())
hl.bind("SUPER + CTRL + LEFT", hl.dsp.group.prev())
hl.bind("SUPER + CTRL + RIGHT", hl.dsp.group.next())
hl.bind("SUPER + ALT + mouse_down", hl.dsp.group.next())
hl.bind("SUPER + ALT + mouse_up", hl.dsp.group.prev())
for index = 1, 5 do
  hl.bind("SUPER + ALT + code:" .. (index + 9), hl.dsp.group.active({ index = index }))
end
