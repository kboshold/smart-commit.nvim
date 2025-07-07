-- Smart Commit Configuration System
-- Author: kboshold

local predefined = require("smart-commit.predefined")

local M = {}

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

-- Function to refresh debug flag (useful for runtime changes)
local function refresh_debug_flag()
  debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"
end

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
  predefined_tasks = {
    -- No default predefined tasks - they will be loaded from config files
  },
  tasks = {
    -- No default tasks - they will be loaded from config files
  },
}

-- Find all config files by traversing up from the current directory
---@param filename string The filename to search for
---@return string[] Array of paths to config files, ordered from root to current directory
local function find_all_files_upwards(filename)
  local files = {}
  local current_dir = vim.fn.getcwd()
  
  -- Collect all directories from current to root
  local directories = {}
  local dir = current_dir
  
  while true do
    table.insert(directories, 1, dir) -- Insert at beginning to get root-to-current order
    
    local parent_dir = vim.fn.fnamemodify(dir, ":h")
    if parent_dir == dir then
      -- We've reached the root directory
      break
    end
    dir = parent_dir
  end
  
  -- Check each directory for the config file
  for _, directory in ipairs(directories) do
    local path = directory .. "/" .. filename
    if vim.fn.filereadable(path) == 1 then
      table.insert(files, path)
    end
  end
  
  return files
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
---@param user_predefined_tasks table<string, SmartCommitTask> User-defined predefined tasks
---@return table<string, SmartCommitTask|false> Processed task configurations
local function process_tasks(tasks, user_predefined_tasks)
  local result = {}
  user_predefined_tasks = user_predefined_tasks or {}

  -- Helper function to get a predefined task (built-in or user-defined)
  local function get_predefined_task(id)
    -- First check user-defined predefined tasks
    if user_predefined_tasks[id] then
      return user_predefined_tasks[id]
    end
    -- Then check built-in predefined tasks
    return predefined.get(id)
  end

  -- First pass: handle shorthand syntax and copy tasks without 'extend'
  for id, task in pairs(tasks) do
    -- Handle shorthand syntax: ["task-id"] = true
    if type(task) == "boolean" and task == true then
      -- Look for the predefined task
      local predefined_task = get_predefined_task(id)
      if predefined_task then
        -- Create a copy of the predefined task
        local task_copy = vim.deepcopy(predefined_task)
        -- Ensure the task has the correct ID
        task_copy.id = id
        result[id] = task_copy
      else
        vim.notify("Unknown predefined task: " .. id, vim.log.levels.WARN)
      end
    -- Handle regular tasks without 'extend'
    elseif type(task) == "table" and task ~= false and not task.extend then
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

      -- Check if it's a predefined task (user-defined or built-in)
      local predefined_task = get_predefined_task(task.extend)
      if predefined_task then
        base_task = vim.deepcopy(predefined_task)
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
  -- Refresh debug flag in case it was changed at runtime
  refresh_debug_flag()
  
  local config = vim.deepcopy(M.defaults)
  local all_predefined_tasks = {}
  local all_configs = {}

  -- 1. Load user global config from ~/.smart-commit.lua
  local user_config_path = vim.fn.expand("~/.smart-commit.lua")
  local user_config = load_lua_file(user_config_path)
  if user_config then
    table.insert(all_configs, { path = user_config_path, config = user_config })
  end

  -- 2. Load all .smart-commit.lua files from root to current directory
  local project_config_paths = find_all_files_upwards(".smart-commit.lua")
  for _, config_path in ipairs(project_config_paths) do
    local project_config = load_lua_file(config_path)
    if project_config then
      table.insert(all_configs, { path = config_path, config = project_config })
    end
  end

  -- Debug: Show which config files were loaded
  if debug_enabled then
    print("Smart Commit: Loading config files:")
    for _, config_entry in ipairs(all_configs) do
      print("  - " .. config_entry.path)
      if config_entry.config.predefined_tasks then
        local predefined_count = vim.tbl_count(config_entry.config.predefined_tasks)
        print("    → " .. predefined_count .. " predefined tasks")
      end
      if config_entry.config.tasks then
        local tasks_count = vim.tbl_count(config_entry.config.tasks)
        print("    → " .. tasks_count .. " tasks")
      end
    end
  end

  -- 3. Register all predefined tasks from all config files first
  for _, config_entry in ipairs(all_configs) do
    local cfg = config_entry.config
    if cfg.predefined_tasks then
      for id, task in pairs(cfg.predefined_tasks) do
        -- Ensure the task has the correct ID
        task.id = id
        all_predefined_tasks[id] = task
        -- Register with the predefined tasks system
        predefined.register(id, task)
        
        if debug_enabled then
          print("Smart Commit: Registered predefined task '" .. id .. "' from " .. config_entry.path)
        end
      end
    end
  end

  -- 4. Process and merge all configurations
  for _, config_entry in ipairs(all_configs) do
    local cfg = config_entry.config
    
    -- Process tasks with access to all predefined tasks
    if cfg.tasks then
      cfg.tasks = process_tasks(cfg.tasks, all_predefined_tasks)
    end
    
    -- Merge configuration (later configs override earlier ones)
    config = vim.tbl_deep_extend("force", config, cfg)
  end

  if debug_enabled then
    print("Smart Commit: Final config has " .. vim.tbl_count(config.tasks or {}) .. " tasks")
  end

  return config
end

-- Expose process_tasks function for use in other modules
M.process_tasks = process_tasks

return M
