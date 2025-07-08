-- Smart Commit Task Runner - Task Executor
-- Author: kboshold

local callbacks = require("smart-commit.runner.callbacks")
local debug_module = require("smart-commit.debug")
local processes = require("smart-commit.runner.processes")
local state = require("smart-commit.runner.state")
local timers = require("smart-commit.runner.timers")
local ui_manager = require("smart-commit.runner.ui_manager")

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

---@class SmartCommitRunnerExecutor
local M = {}

-- Run a single task
---@param win_id number The window ID of the commit buffer
---@param task SmartCommitTask The task to run
---@param all_tasks table<string, SmartCommitTask|false>|nil All tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.run_task(win_id, task, all_tasks, config)
  -- Ensure task has an ID
  if not task.id then
    vim.notify("Task has no ID, skipping", vim.log.levels.ERROR)
    return
  end

  -- Initialize task state (preserve existing callback information)
  local existing_task = state.get_task(task.id)
  local existing_is_callback = existing_task and existing_task.is_callback
  local existing_parent_task = existing_task and existing_parent_task

  state.set_task_running(task.id)

  if debug_enabled and existing_is_callback then
    debug_module.log(
      "Preserving callback status for task '"
        .. task.id
        .. "' in run_task (parent: "
        .. tostring(existing_parent_task)
        .. ")"
    )
  end

  -- Start UI update timer if not already running
  timers.start_ui_updates(win_id, all_tasks, config)

  -- Get the buffer ID for the commit buffer
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  -- Check if task has a handler (highest priority)
  if task.handler and type(task.handler) == "function" then
    M.execute_handler(win_id, buf_id, task, all_tasks, config)
    return
  end

  -- Check if task has a function (second priority)
  if task.fn and type(task.fn) == "function" then
    M.execute_function(win_id, task, all_tasks, config)
    return
  end

  -- Determine the command to run (lowest priority)
  local cmd = M.get_command(task)

  -- If cmd is nil or empty, skip this task
  if not cmd or cmd == "" then
    M.handle_empty_command(win_id, task, all_tasks, config)
    return
  end

  -- Run the command
  M.execute_command(win_id, buf_id, task, cmd, all_tasks, config)
end

-- Execute a handler-based task
---@param win_id number The window ID
---@param buf_id number The buffer ID
---@param task SmartCommitTask The task
---@param all_tasks table All tasks configuration
---@param config table The configuration
function M.execute_handler(win_id, buf_id, task, all_tasks, config)
  -- Create context for the handler
  local ctx = {
    win_id = win_id,
    buf_id = buf_id,
    runner = require("smart-commit.runner"), -- Circular dependency handled at runtime
    task = task,
    config = config,
  }

  -- Run the handler
  local result = task.handler(ctx)

  -- Process the result
  if type(result) == "boolean" then
    -- Boolean result indicates success/failure
    local state_updated =
      state.safe_update_task_state(task.id, result and state.TASK_STATE.SUCCESS or state.TASK_STATE.FAILED)
    if state_updated then
      state.set_task_end_time(task.id)

      -- Prepare result information for callbacks
      local task_result = {
        success = result,
        output = state.get_task(task.id).output,
      }

      -- Execute callbacks
      M.handle_task_completion(task, task_result, win_id, all_tasks, config)
    end
    vim.schedule(function()
      ui_manager.update_ui(win_id, all_tasks, config)
      ui_manager.update_signs(win_id)
    end)
  elseif type(result) == "string" then
    -- String result is a command to run
    M.execute_command(win_id, buf_id, task, result, all_tasks, config)
  else
    -- Nil result means the handler is managing the task state asynchronously
    vim.schedule(function()
      ui_manager.update_ui(win_id, all_tasks, config)
      ui_manager.update_signs(win_id)
    end)
  end
end

-- Execute a function-based task
---@param win_id number The window ID
---@param task SmartCommitTask The task
---@param all_tasks table All tasks configuration
---@param config table The configuration
function M.execute_function(win_id, task, all_tasks, config)
  local result = task.fn()

  -- Set end time
  state.set_task_end_time(task.id)

  -- Process the result
  local success = false
  local state_updated = false

  if type(result) == "boolean" then
    success = result
    state_updated =
      state.safe_update_task_state(task.id, result and state.TASK_STATE.SUCCESS or state.TASK_STATE.FAILED)
  elseif type(result) == "table" and result.ok ~= nil then
    success = result.ok
    state_updated =
      state.safe_update_task_state(task.id, result.ok and state.TASK_STATE.SUCCESS or state.TASK_STATE.FAILED)
  else
    success = false
    state_updated = state.safe_update_task_state(task.id, state.TASK_STATE.FAILED)
  end

  -- Execute callbacks if state was updated
  if state_updated then
    local task_result = {
      success = success,
      output = state.get_task(task.id).output,
    }

    if type(result) == "table" then
      task_result.error_message = result.message
    end

    -- Execute callbacks
    M.handle_task_completion(task, task_result, win_id, all_tasks, config)
  end

  vim.schedule(function()
    ui_manager.update_ui(win_id, all_tasks, config)
    ui_manager.update_signs(win_id)
  end)
end

-- Execute a command-based task
---@param win_id number The window ID
---@param buf_id number The buffer ID
---@param task SmartCommitTask The task
---@param cmd string The command to execute
---@param all_tasks table All tasks configuration
---@param config table The configuration
function M.execute_command(win_id, buf_id, task, cmd, all_tasks, config)
  -- Handle special commands like "exit 0" or "exit 1"
  if cmd == "exit 0" then
    local state_updated = state.safe_update_task_state(task.id, state.TASK_STATE.SUCCESS)
    if state_updated then
      state.set_task_end_time(task.id)
      local task_result = {
        success = true,
        exit_code = 0,
        output = state.get_task(task.id).output,
      }
      M.handle_task_completion(task, task_result, win_id, all_tasks, config)
    end
    vim.schedule(function()
      ui_manager.update_ui(win_id, all_tasks, config)
      ui_manager.update_signs(win_id)
    end)
    return
  elseif cmd == "exit 1" then
    local state_updated = state.safe_update_task_state(task.id, state.TASK_STATE.FAILED)
    if state_updated then
      state.set_task_end_time(task.id)
      local task_result = {
        success = false,
        exit_code = 1,
        output = state.get_task(task.id).output,
      }
      M.handle_task_completion(task, task_result, win_id, all_tasks, config)
    end
    vim.schedule(function()
      ui_manager.update_ui(win_id, all_tasks, config)
      ui_manager.update_signs(win_id)
    end)
    return
  end

  -- Execute the command using the process manager
  processes.run_command(win_id, task, cmd, all_tasks, config, function(task_result)
    -- Handle task completion
    M.handle_task_completion(task, task_result, win_id, all_tasks, config)

    -- Update UI
    vim.schedule(function()
      ui_manager.update_ui(win_id, all_tasks, config)
      ui_manager.update_signs(win_id)

      -- Stop timer if all tasks are complete
      if state.all_tasks_complete() then
        timers.stop_ui_updates()
      end
    end)
  end)

  -- Update signs immediately
  ui_manager.update_signs(win_id)
end

-- Get the command to execute for a task
---@param task SmartCommitTask The task
---@return string|nil The command to execute
function M.get_command(task)
  local cmd
  if type(task.command) == "function" then
    -- If command is a function, call it with the task as argument
    cmd = task.command(task)
  else
    -- Otherwise use the command string directly
    cmd = task.command
  end
  return cmd
end

-- Handle empty command case
---@param win_id number The window ID
---@param task SmartCommitTask The task
---@param all_tasks table All tasks configuration
---@param config table The configuration
function M.handle_empty_command(win_id, task, all_tasks, config)
  vim.notify("Empty command for task: " .. task.id .. ", marking as success", vim.log.levels.WARN)
  local state_updated = state.safe_update_task_state(task.id, state.TASK_STATE.SUCCESS)
  if state_updated then
    state.set_task_end_time(task.id)

    -- Execute success callback
    if task.on_success then
      local task_result = {
        success = true,
        output = state.get_task(task.id).output,
      }
      callbacks.execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
    end
  end
  vim.schedule(function()
    ui_manager.update_ui(win_id, all_tasks, config)
    ui_manager.update_signs(win_id)
  end)
end

-- Handle task completion and execute callbacks
---@param task SmartCommitTask The task that completed
---@param task_result table The task result
---@param win_id number The window ID
---@param all_tasks table All tasks configuration
---@param config table The configuration
function M.handle_task_completion(task, task_result, win_id, all_tasks, config)
  if task_result.success and task.on_success then
    if debug_enabled then
      debug_module.log(
        "Task '" .. task.id .. "' succeeded, executing on_success callback: " .. tostring(task.on_success)
      )
    end
    callbacks.execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
  elseif not task_result.success and task.on_fail then
    if debug_enabled then
      debug_module.log("Task '" .. task.id .. "' failed, executing on_fail callback: " .. tostring(task.on_fail))
    end
    callbacks.execute_callback(task.on_fail, task_result, win_id, all_tasks, config, task.id)
  end
end

return M
