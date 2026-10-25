-- 5% steps, 1% with ALT. SHIFT takes the screen to full or lowest brightness.
for _, step in ipairs({ { "", 5 }, { "ALT + ", 1 } }) do
  local mods, pct = step[1], step[2]
  hl.bind(mods .. "XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ " .. pct .. "%+"), { locked = true, repeating = true })
  hl.bind(mods .. "XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. pct .. "%-"), { locked = true, repeating = true })
  hl.bind(mods .. "XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set " .. pct .. "%+"), { locked = true, repeating = true })
  hl.bind(mods .. "XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set " .. pct .. "%-"), { locked = true, repeating = true })
end
hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 100%"), { locked = true })
hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 1%"), { locked = true })
hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd("brightnessctl -d '*kbd_backlight' set 10%+"), { locked = true, repeating = true })
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d '*kbd_backlight' set 10%-"), { locked = true, repeating = true })

hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("ALT + XF86AudioPlay", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("ALT + SHIFT + XF86AudioPlay", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86Eject", hl.dsp.exec_cmd("eject"), { locked = true })
