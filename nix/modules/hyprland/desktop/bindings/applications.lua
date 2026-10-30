local apps = require("desktop.apps")

-- Focuses the first window whose class or title contains pattern, or runs
-- command if there is none, as Omarchy's omarchy-launch-or-focus does.
local function launch_or_focus(pattern, command)
  return function()
    for _, window in ipairs(hl.get_windows()) do
      if window.class:lower():find(pattern, 1, true) or window.title:lower():find(pattern, 1, true) then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
        return
      end
    end
    hl.exec_cmd(command)
  end
end

-- A Chromium app window. As on the laptop, the Default profile is for work and
-- Profile 1 personal. Its class is chrome-<host>__<path>-<profile>, which is
-- what the launch_or_focus patterns below match.
local function webapp(url, profile)
  return "chromium --app=" .. url .. " '--profile-directory=" .. (profile or "Default") .. "'"
end

hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(apps.terminal))
hl.bind("SUPER + SHIFT + RETURN", hl.dsp.exec_cmd(apps.browser))
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd(apps.browser))
hl.bind("SUPER + SHIFT + ALT + B", hl.dsp.exec_cmd(apps.browser .. " --private-window"))
hl.bind("SUPER + SHIFT + F", hl.dsp.exec_cmd(apps.file_manager))
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(apps.terminal .. " -e nvim"))
hl.bind("SUPER + SHIFT + T", apps.tui("btop"))
hl.bind("SUPER + SHIFT + G", launch_or_focus("goland", "goland"))

hl.bind("SUPER + SHIFT + M", launch_or_focus("tidal", webapp("https://tidal.com")))
hl.bind("SUPER + SHIFT + W", launch_or_focus("web.whatsapp.com", webapp("https://web.whatsapp.com/")))
hl.bind("SUPER + SHIFT + Y", launch_or_focus("youtube.com", webapp("https://youtube.com/")))
hl.bind("SUPER + SHIFT + C", launch_or_focus("calendar.google.com", webapp("https://calendar.google.com")))
hl.bind("SUPER + ALT + M", launch_or_focus("mail.google.com", webapp("https://mail.google.com")))
hl.bind("SUPER + ALT + G", launch_or_focus("github.com__pulls_inbox", webapp("https://github.com/pulls/inbox")))

hl.bind("SUPER + SHIFT + P", launch_or_focus("photos.wvl.app", webapp("https://photos.wvl.app/")))
