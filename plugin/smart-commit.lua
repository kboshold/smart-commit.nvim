-- Smart Commit Plugin Entry Point
-- This file is loaded automatically by Neovim

-- Don't load twice
if vim.g.loaded_smart_commit then
  return
end
vim.g.loaded_smart_commit = true

-- Create user commands
vim.api.nvim_create_user_command("SmartCommitKill", function()
  require("smart-commit").kill_all_tasks()
  vim.notify("Smart Commit: All tasks killed", vim.log.levels.INFO)
end, {
  desc = "Kill all running Smart Commit tasks",
})

vim.api.nvim_create_user_command("SmartCommitRun", function()
  require("smart-commit").run_tasks()
end, {
  desc = "Manually run Smart Commit tasks",
})

vim.api.nvim_create_user_command("SmartCommitToggle", function()
  require("smart-commit").toggle()
  local smart_commit = require("smart-commit")
  local status = smart_commit.config.defaults.auto_run and "enabled" or "disabled"
  vim.notify("Smart Commit: " .. status, vim.log.levels.INFO)
end, {
  desc = "Toggle Smart Commit auto-run",
})

vim.api.nvim_create_user_command("SmartCommitEnable", function()
  require("smart-commit").enable()
  vim.notify("Smart Commit: enabled", vim.log.levels.INFO)
end, {
  desc = "Enable Smart Commit auto-run",
})

vim.api.nvim_create_user_command("SmartCommitDisable", function()
  require("smart-commit").disable()
  vim.notify("Smart Commit: disabled", vim.log.levels.INFO)
end, {
  desc = "Disable Smart Commit auto-run",
})

-- The plugin will be initialized by the user via require("smart-commit").setup()
