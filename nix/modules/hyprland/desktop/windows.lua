-- The terminal UIs behind the bar's icons, and system-update.
hl.window_rule({
  name = "float-tuis",
  match = { class = "TUI\\.float" },
  float = true,
  size = "875 600",
  center = true,
})
