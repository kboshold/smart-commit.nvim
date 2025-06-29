-- Smart Commit Configuration System
-- Author: kboshold

local predefined = require("smart-commit.predefined")

local M = {}

-- Default configuration
---@type SmartCommitConfig
M.defaults = {
  defaults = {
    auto_run = true,
    sign_column = true,
    hide_skipped = false, -- Whether to hide skipped tasks in the UI
    status_window = {
      enabled = true,
      position = "bottom",
      refresh_rate = 100,
    },
  },
  tasks = {
    -- No default tasks - they will be loaded from config files
  },
}

-- Find a file by traversing up from the current directory
---@param filename string The filename to search for
---@return string|nil The path to the file if found, nil otherwise
local function find_file_upwards(filename)
  -- First, try to find the file in the Git repository root
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
  if vim.v.shell_error == 0 and git_root ~= "" then
    local git_root_path = git_root .. "/" .. filename
    if vim.fn.filereadable(git_root_path) == 1 then
      return git_root_path
    end
  end

  -- If not found in Git root, try traversing up from the current directory
  local current_dir = vim.fn.getcwd()
  local path = current_dir .. "/" .. filename

  while true do
    if vim.fn.filereadable(path) == 1 then
      return path
    end

    -- Move up one directory
    local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
    if parent_dir == current_dir then
      -- We've reached the root directory
      break
    end

    current_dir = parent_dir
    path = current_dir .. "/" .. filename
  end

  return nil
end

-- Load a Lua file and return its contents
---@param path string The path to the Lua file
---@return table|nil The contents of the file if successful, nil otherwise
local function load_lua_file(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local success, result = pcall(dofile, path)
  if not success then
    vim.notify("Error loading " .. path .. ": " .. result, vim.log.levels.ERROR)
    return nil
  end

  return result
end

-- Process task configurations, resolving 'extend' references
---@param tasks table<string, SmartCommitTask|boolean> Raw task configurations
---@return table<string, SmartCommitTask|false> Processed task configurations
local function process_tasks(tasks)
  local result = {}

  -- First pass: handle shorthand syntax and copy tasks without 'extend'
  for id, task in pairs(tasks) do
    -- Handle shorthand syntax: ["predefined:task"] = true
    if type(task) == "boolean" and task == true then
      -- Check if the ID is a predefined task reference
      local predefined_id = id:match("^([%w:]+)$")
      if predefined_id and predefined.get(predefined_id) then
        -- Create a task that extends the predefined task
        local base_task = vim.deepcopy(predefined.get(predefined_id))
        -- Use the original ID to avoid duplicates
        result[id] = base_task
      else
        vim.notify("Unknown predefined task: " .. id, vim.log.levels.WARN)
      end
    -- Handle regular tasks without 'extend'
    elseif task ~= false and not task.extend then
      -- Make a copy of the task
      local task_copy = vim.deepcopy(task)

      -- If id is not set, use the key as the id
      if not task_copy.id then
        task_copy.id = id
      end

      result[id] = task_copy
    end
  end

  -- Second pass: process tasks with 'extend'
  for id, task in pairs(tasks) do
    if type(task) == "table" and task.extend then
      -- Find the base task
      local base_task = nil

      -- Check if it's a predefined task
      if predefined.get(task.extend) then
        base_task = vim.deepcopy(predefined.get(task.extend))
      -- Check if it's already in our result set
      elseif result[task.extend] then
        base_task = vim.deepcopy(result[task.extend])
      end

      if base_task then
        -- Make a copy of the task
        local task_copy = vim.deepcopy(task)

        -- If id is not set, use the key as the id
        if not task_copy.id then
          task_copy.id = id
        end

        -- Merge the task with the base task (task properties override base)
        local merged_task = vim.tbl_deep_extend("force", base_task, task_copy)
        -- Remove the 'extend' property as it's no longer needed
        merged_task.extend = nil
        result[id] = merged_task
      else
        -- Error: Task extends an unknown task
        local error_msg = "Task '" .. id .. "' extends unknown task '" .. task.extend .. "'"
        vim.notify(error_msg, vim.log.levels.ERROR)

        -- Set the task to false to disable it
        result[id] = false
      end
    end
  end

  -- Third pass: handle disabled tasks (set to false)
  for id, task in pairs(tasks) do
    if task == false then
      result[id] = false
    end
  end

  return result
end

-- Load configuration from various sources
---@return SmartCommitConfig The merged configuration
function M.load_config()
  local config = vim.deepcopy(M.defaults)

  -- 1. Load user global config from ~/.smart-commit.lua
  local user_config_path = vim.fn.expand("~/.smart-commit.lua")
  local user_config = load_lua_file(user_config_path)
  if user_config then
    -- Process tasks before merging
    if user_config.tasks then
      user_config.tasks = process_tasks(user_config.tasks)
    end
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- 2. Load project-specific config from .smart-commit.lua in the project
  local project_config_path = find_file_upwards(".smart-commit.lua")
  if project_config_path then
    local project_config = load_lua_file(project_config_path)
    if project_config then
      -- Process tasks before merging
      if project_config.tasks then
        project_config.tasks = process_tasks(project_config.tasks)
      end
      config = vim.tbl_deep_extend("force", config, project_config)
    end
  end

  return config
end

return M
