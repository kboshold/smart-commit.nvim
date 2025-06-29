-- Smart Commit Plugin Entry Point
-- This file is loaded automatically by Neovim

-- Don't load twice
if vim.g.loaded_smart_commit then
  return
end
vim.g.loaded_smart_commit = true

-- The plugin will be initialized by the user via require("smart-commit").setup()
