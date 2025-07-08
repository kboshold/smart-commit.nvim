-- Smart Commit Task Runner - Process Management
-- Author: kboshold

local debug_module = require("smart-commit.debug")
local state = require("smart-commit.runner.state")

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

---@class SmartCommitRunnerProcesses
local M = {}

-- Store active processes for cleanup
---@type table<string, any>
local active_processes = {}

-- Run a shell command for a task
---@param win_id number The window ID of the commit buffer
---@param task SmartCommitTask The task to run
---@param cmd string The command to run
---@param all_tasks table<string, SmartCommitTask|false>|nil All tasks configuration
---@param config SmartCommitConfig|nil The full configuration
---@param completion_callback function Callback to execute when command completes
function M.run_command(win_id, task, cmd, all_tasks, config, completion_callback)
  -- Split the command into parts for vim.system
  local cmd_parts = {}
  for part in cmd:gmatch("%S+") do
    table.insert(cmd_parts, part)
  end

  -- Prepare options for vim.system
  local options = {
    stdout = function(err, data)
      if data then
        state.append_task_output(task.id, data)
      end
    end,
    stderr = function(err, data)
      if data then
        state.append_task_output(task.id, data)
      end
    end,
  }

  -- Set working directory if specified
  if task.cwd then
    options.cwd = task.cwd
  end

  -- Set environment variables if specified
  if task.env and type(task.env) == "table" then
    options.env = task.env
  end

  -- Log command execution in debug mode
  if debug_enabled then
    debug_module.log("Executing command for task '" .. task.id .. "': " .. cmd)
    if task.cwd then
      debug_module.log("Working directory: " .. task.cwd)
    end
    if task.env and type(task.env) == "table" then
      debug_module.log("Environment variables:")
      for k, v in pairs(task.env) do
        debug_module.log("  " .. k .. "=" .. v)
      end
    end

    -- Update the debug window - use pcall to handle potential errors in fast event context
    pcall(function()
      local debug = require("smart-commit.debug")
      if debug.is_enabled() then
        local ui = require("smart-commit.ui")
        local content = ui.get_current_content and ui.get_current_content(win_id) or {}
        debug.update(win_id, content)
      end
    end)
  end

  -- Run the command asynchronously
  local process = vim.system(cmd_parts, options, function(obj)
    -- Remove from active processes
    active_processes[task.id] = nil

    -- Update task state based on exit code and set end_time
    state.set_task_end_time(task.id)

    -- Prepare result information for callbacks
    local task_result = {
      success = obj.code == 0,
      exit_code = obj.code,
      output = state.get_task(task.id).output,
      stdout = obj.stdout or "",
      stderr = obj.stderr or "",
    }

    -- Log command output in debug mode
    if debug_enabled then
      debug_module.log("Task '" .. task.id .. "' command: " .. cmd)
      debug_module.log("Task '" .. task.id .. "' exit code: " .. obj.code)
      if obj.stdout and obj.stdout ~= "" then
        debug_module.log(obj.stdout, "INFO", true)
      end
      if obj.stderr and obj.stderr ~= "" then
        debug_module.log(obj.stderr, "ERROR", true)
      end

      -- Update the debug window - use pcall to handle potential errors in fast event context
      pcall(function()
        local debug = require("smart-commit.debug")
        if debug.is_enabled() then
          local ui = require("smart-commit.ui")
          local content = ui.get_current_content and ui.get_current_content(win_id) or {}
          debug.update(win_id, content)
        end
      end)
    end

    -- Only update state if the task hasn't been aborted
    local state_updated = false
    if obj.code == 0 then
      state_updated = state.safe_update_task_state(task.id, state.TASK_STATE.SUCCESS)
    else
      if debug_enabled then
        debug_module.log("Task '" .. task.id .. "' failed with exit code " .. obj.code)
      end
      state_updated = state.safe_update_task_state(task.id, state.TASK_STATE.FAILED)
    end

    -- Execute completion callback if state was updated (not aborted)
    if state_updated and completion_callback then
      completion_callback(task_result)
    end
  end)

  -- Store the process handle for potential cleanup
  active_processes[task.id] = process
end

-- Kill all active processes
function M.kill_all_tasks()
  -- Kill all active processes
  for task_id, process in pairs(active_processes) do
    if process and process.pid then
      -- Try to kill the process gracefully first, then forcefully
      pcall(function()
        process:kill(15) -- SIGTERM
      end)

      -- After a short delay, force kill if still running
      vim.defer_fn(function()
        pcall(function()
          process:kill(9) -- SIGKILL
        end)
      end, 1000)

      -- Update task state to indicate it was killed
      state.set_task_aborted(task_id, "[Process aborted by user]")
    end
  end

  -- Clear the active processes table
  active_processes = {}
end

-- Get active process count
---@return number The number of active processes
function M.get_active_process_count()
  local count = 0
  for _ in pairs(active_processes) do
    count = count + 1
  end
  return count
end

-- Check if a task has an active process
---@param task_id string The task ID
---@return boolean True if the task has an active process
function M.has_active_process(task_id)
  return active_processes[task_id] ~= nil
end

return M
