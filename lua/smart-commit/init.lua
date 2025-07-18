-- Smart Commit Plugin for Neovim
-- Author: kboshold

-- Import dependencies
local config_loader = require("smart-commit.config")
local runner = require("smart-commit.runner")
local types = require("smart-commit.types")
local ui = require("smart-commit.ui")

---@class SmartCommit
local M = {}

-- Default configuration
---@type SmartCommitConfig
M.config = config_loader.defaults

-- Setup function to initialize the plugin with user config
---@param opts SmartCommitConfig|nil User configuration table
---@return SmartCommit The plugin instance
function M.setup(opts)
  -- Register predefined tasks from setup() first if provided
  -- This ensures they're available when loading file configs
  if opts and opts.predefined_tasks then
    local predefined = require("smart-commit.predefined")
    for id, task in pairs(opts.predefined_tasks) do
      -- Ensure the task has the correct ID
      task.id = id
      -- Register with the predefined tasks system
      predefined.register(id, task)
    end
  end

  -- Load configuration from files (now with setup predefined tasks available)
  local file_config = config_loader.load_config()

  -- Start with defaults, then apply file config
  M.config = vim.tbl_deep_extend("force", M.config, file_config)

  -- Finally apply setup opts (this can override file config)
  if opts then
    -- Process setup tasks with access to all predefined tasks (including from files)
    if opts.tasks then
      local predefined = require("smart-commit.predefined")
      local all_predefined_tasks = {}

      -- Collect all registered predefined tasks
      for id, task in pairs(predefined.tasks) do
        all_predefined_tasks[id] = task
      end

      -- Process setup tasks
      local processed_setup_tasks = config_loader.process_tasks(opts.tasks, all_predefined_tasks)
      opts.tasks = processed_setup_tasks
    end

    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  -- Only set up autocommands if enabled
  if M.config.defaults.auto_run then
    M.create_autocommands()
  end

  return M
end

-- Create autocommands for detecting git commit buffers
function M.create_autocommands()
  local augroup = vim.api.nvim_create_augroup("SmartCommit", { clear = true })

  -- Track which buffers have already been processed
  local processed_buffers = {}

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    pattern = "COMMIT_EDITMSG",
    callback = function(args)
      -- Check if this buffer has already been processed
      local bufnr = args.buf
      if processed_buffers[bufnr] then
        return
      end

      -- Mark this buffer as processed
      processed_buffers[bufnr] = true

      -- Check if auto_run is enabled and if SMART_COMMIT_ENABLED env var is not set to 0
      local env_disabled = vim.env.SMART_COMMIT_ENABLED == "0"

      if M.config.defaults.auto_run and not env_disabled then
        M.on_commit_buffer_open(bufnr)
      end
    end,
    desc = "Smart Commit activation on git commit",
  })

  -- Clean up processed buffers when they are deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    pattern = "COMMIT_EDITMSG",
    callback = function(args)
      processed_buffers[args.buf] = nil
      -- Also kill tasks when buffer is deleted
      runner.kill_all_tasks()
    end,
    desc = "Clean up Smart Commit tracking for deleted buffers",
  })
end

-- Handler for when a commit buffer is opened
---@param bufnr number The buffer number of the commit buffer
function M.on_commit_buffer_open(bufnr)
  local win_id = vim.fn.bufwinid(bufnr)

  -- Debug: Print the loaded tasks
  local task_count = 0
  local task_ids = {}
  for id, task in pairs(M.config.tasks) do
    if task then
      task_count = task_count + 1
      table.insert(task_ids, id)
    end
  end

  -- Show initial header
  ---@type StickyHeaderContent
  local content = {
    {
      { text = "Smart Commit ", highlight_group = "Title" },
      { text = "activated", highlight_group = "String" },
    },
    {
      { text = "Status: ", highlight_group = "Label" },
      { text = "Running tasks...", highlight_group = "DiagnosticInfo" },
    },
  }

  -- Show the header
  ui.set(win_id, content)

  -- Run tasks from configuration with dependency tracking
  runner.run_tasks_with_dependencies(win_id, M.config.tasks, M.config)
end

-- Enable the plugin
function M.enable()
  M.config.defaults.auto_run = true
  M.create_autocommands()
end

-- Disable the plugin
function M.disable()
  M.config.defaults.auto_run = false
  vim.api.nvim_del_augroup_by_name("SmartCommit")
end

-- Toggle the plugin state
function M.toggle()
  if M.config.defaults.auto_run then
    M.disable()
  else
    M.enable()
  end
end

-- Register a custom task
---@param id string The task ID
---@param task SmartCommitTask The task configuration
function M.register_task(id, task)
  -- Ensure task has an ID
  task.id = id

  -- Add to the tasks configuration
  M.config.tasks[id] = task
end

-- Run tasks manually
---@param win_id number|nil The window ID to run tasks in (defaults to current window)
function M.run_tasks()
  local win_id = vim.api.nvim_get_current_win()
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  -- Show initial header
  ---@type StickyHeaderContent
  local content = {
    {
      { text = "Smart Commit ", highlight_group = "Title" },
      { text = "Manual Run", highlight_group = "String" },
    },
    {
      { text = "Status: ", highlight_group = "Label" },
      { text = "Running tasks...", highlight_group = "DiagnosticInfo" },
    },
  }

  -- Show the header
  ui.set(win_id, content)

  -- Run tasks from configuration with dependency tracking
  runner.run_tasks_with_dependencies(win_id, M.config.tasks, M.config)
end

-- Kill all running tasks
function M.kill_all_tasks()
  runner.kill_all_tasks()
end

-- Initialize with default settings if not explicitly set up
M.setup()

-- Create user commands
vim.api.nvim_create_user_command("SmartCommitLog", function()
  local debug = require("smart-commit.debug")
  debug.show_log_window(true)
end, {
  desc = "Show Smart Commit logs",
})

return M
