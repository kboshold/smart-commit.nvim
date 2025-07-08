-- Smart Commit Task Runner - State Management
-- Author: kboshold

local debug_module = require("smart-commit.debug")

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

---@class SmartCommitRunnerState
local M = {}

-- Task states
M.TASK_STATE = {
  PENDING = "pending",
  WAITING = "waiting", -- New state for tasks waiting on dependencies
  RUNNING = "running",
  SUCCESS = "success",
  FAILED = "failed",
  SKIPPED = "skipped", -- New state for tasks that were skipped due to conditions
  ABORTED = "aborted", -- New state for tasks that were killed/aborted
}

-- Current task state
---@type table<string, {state: string, output: string, start_time: number, end_time: number?, process: any?, is_callback?: boolean, parent_task?: string}>
M.tasks = {}

-- Helper function to safely update task state (prevents overriding ABORTED state and preserves callback info)
---@param task_id string The task ID
---@param new_state string The new state to set
---@return boolean success Whether the state was updated
function M.safe_update_task_state(task_id, new_state)
  if M.tasks[task_id] and M.tasks[task_id].state ~= M.TASK_STATE.ABORTED then
    -- Preserve ALL existing fields when updating state
    local existing_task = M.tasks[task_id]
    local old_is_callback = existing_task.is_callback
    local old_parent = existing_task.parent_task

    M.tasks[task_id].state = new_state

    -- Explicitly preserve callback information if it exists
    if old_is_callback ~= nil then
      M.tasks[task_id].is_callback = old_is_callback
      if debug_enabled and old_is_callback then
        debug_module.log(
          "Preserving callback status for task '" .. task_id .. "' (parent: " .. tostring(old_parent) .. ")"
        )
      end
    end
    if old_parent ~= nil then
      M.tasks[task_id].parent_task = old_parent
    end
    return true
  end
  return false
end

-- Initialize a task in the state
---@param task_id string The task ID
---@param task_config SmartCommitTask The task configuration
---@param is_callback boolean Whether this is a callback task
---@param parent_task_id string|nil The parent task ID if this is a callback
function M.initialize_task(task_id, task_config, is_callback, parent_task_id)
  if debug_enabled then
    if is_callback then
      debug_module.log(
        "Creating NEW callback task '" .. task_id .. "' for parent '" .. (parent_task_id or "unknown") .. "'"
      )
    else
      debug_module.log("Initializing regular task '" .. task_id .. "'")
    end
  end

  -- Ensure we don't overwrite existing callback tasks
  if not M.tasks[task_id] then
    M.tasks[task_id] = {
      state = M.TASK_STATE.PENDING,
      output = "",
      start_time = 0,
      depends_on = task_config.depends_on or {},
      is_callback = is_callback or false,
      parent_task = parent_task_id,
    }
  else
    -- If task already exists (e.g., callback task), preserve callback status
    local existing_is_callback = M.tasks[task_id].is_callback
    local existing_parent = M.tasks[task_id].parent_task
    if debug_enabled then
      debug_module.log(
        "Task '" .. task_id .. "' already exists, preserving callback status: " .. tostring(existing_is_callback)
      )
    end
    M.tasks[task_id].state = M.TASK_STATE.PENDING
    M.tasks[task_id].output = ""
    M.tasks[task_id].start_time = 0
    M.tasks[task_id].depends_on = task_config.depends_on or {}
    M.tasks[task_id].is_callback = existing_is_callback or is_callback or false
    M.tasks[task_id].parent_task = existing_parent or parent_task_id
  end
end

-- Mark a task as a callback task
---@param task_id string The task ID
---@param parent_task_id string The parent task ID
function M.mark_as_callback(task_id, parent_task_id)
  if M.tasks[task_id] then
    if debug_enabled then
      debug_module.log("Marking EXISTING task '" .. task_id .. "' as callback for parent '" .. parent_task_id .. "'")
      debug_module.log("Task '" .. task_id .. "' current is_callback: " .. tostring(M.tasks[task_id].is_callback))
    end
    M.tasks[task_id].is_callback = true
    M.tasks[task_id].parent_task = parent_task_id
    if debug_enabled then
      debug_module.log("Task '" .. task_id .. "' updated is_callback: " .. tostring(M.tasks[task_id].is_callback))
    end
  end
end

-- Set task as running
---@param task_id string The task ID
function M.set_task_running(task_id)
  if M.tasks[task_id] then
    -- Preserve existing callback information
    local existing_is_callback = M.tasks[task_id].is_callback
    local existing_parent_task = M.tasks[task_id].parent_task

    M.tasks[task_id].state = M.TASK_STATE.RUNNING
    M.tasks[task_id].start_time = vim.loop.now()
    M.tasks[task_id].is_callback = existing_is_callback or false
    M.tasks[task_id].parent_task = existing_parent_task

    if debug_enabled and existing_is_callback then
      debug_module.log(
        "Preserving callback status for task '"
          .. task_id
          .. "' in set_task_running (parent: "
          .. tostring(existing_parent_task)
          .. ")"
      )
    end
  end
end

-- Set task end time
---@param task_id string The task ID
function M.set_task_end_time(task_id)
  if M.tasks[task_id] then
    M.tasks[task_id].end_time = vim.loop.now()
  end
end

-- Append output to task
---@param task_id string The task ID
---@param output string The output to append
function M.append_task_output(task_id, output)
  if M.tasks[task_id] then
    M.tasks[task_id].output = M.tasks[task_id].output .. output
  end
end

-- Set task as aborted
---@param task_id string The task ID
---@param message string|nil Optional message to append
function M.set_task_aborted(task_id, message)
  if M.tasks[task_id] then
    M.tasks[task_id].state = M.TASK_STATE.ABORTED
    M.tasks[task_id].end_time = vim.loop.now()
    if message then
      M.tasks[task_id].output = M.tasks[task_id].output .. "\n" .. message
    end
  end
end

-- Check if all tasks are complete
---@return boolean True if all tasks are complete
function M.all_tasks_complete()
  for _, task in pairs(M.tasks) do
    if
      task.state == M.TASK_STATE.RUNNING
      or task.state == M.TASK_STATE.PENDING
      or task.state == M.TASK_STATE.WAITING
    then
      return false
    end
  end
  return true
end

-- Get task by ID
---@param task_id string The task ID
---@return table|nil The task state
function M.get_task(task_id)
  return M.tasks[task_id]
end

-- Check if task is in a specific state
---@param task_id string The task ID
---@param state string The state to check
---@return boolean True if task is in the specified state
function M.is_task_in_state(task_id, state)
  local task = M.tasks[task_id]
  return task and task.state == state
end

-- Get tasks in a specific state
---@param state string The state to filter by
---@return table<string, table> Tasks in the specified state
function M.get_tasks_in_state(state)
  local result = {}
  for id, task in pairs(M.tasks) do
    if task.state == state then
      result[id] = task
    end
  end
  return result
end

-- Clear all tasks
function M.clear_tasks()
  M.tasks = {}
end

return M
