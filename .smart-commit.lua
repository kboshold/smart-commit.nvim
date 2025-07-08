-- User-level Smart Commit configuration
-- This file is loaded from the user's home directory

return {
  defaults = {
    auto_run = true,
    sign_column = true,
    status_window = {
      enabled = true,
      position = "bottom",
      refresh_rate = 100,
    },
  },
  predefined_tasks = {
    ["lint:stylua-fix"] = {
      label = "Stylua Fix",
      icon = "",
      command = "stylua .",
    },
  },
  tasks = {
    ["copilot:message"] = true,

    ["lint:stylua"] = {
      label = "Stylua",
      icon = "",
      command = "stylua --check .",
      on_fail = "lint:stylua-fix",
    },
  },
}
