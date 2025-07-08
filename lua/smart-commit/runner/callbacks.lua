-- Smart Commit Task Runner - Callback System
-- Author: kboshold

local debug_module = require("smart-commit.debug")
local state = require("smart-commit.runner.state")

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

---@class SmartCommitRunnerCallbacks
local M = {}

-- Execute a task callback (either run another task or call a function)
---@param callback string | function | table The callback to execute (string, function, or array of callbacks)
---@param result table The task result information
---@param win_id number The window ID
---@param all_tasks table All tasks configuration
---@param config table The full configuration
---@param parent_task_id string|nil The ID of the task that triggered this callback
function M.execute_callback(callback, result, win_id, all_tasks, config, parent_task_id)
  -- Handle array of callbacks
  if type(callback) == "table" and not vim.is_callable(callback) then
    if debug_enabled then
      debug_module.log("Executing array of " .. #callback .. " callbacks")
    end

    -- Execute each callback in the array
    for i, single_callback in ipairs(callback) do
      -- For the first callback in the array, use the original parent
      -- For subsequent callbacks, use the previous callback as parent
      local effective_parent = parent_task_id
      if i > 1 and type(callback[i - 1]) == "string" then
        -- If the previous callback was a task (string), use it as the parent
        effective_parent = callback[i - 1]
        if debug_enabled then
          debug_module.log("Using previous callback '" .. effective_parent .. "' as parent for callback #" .. i)
        end
      end

      M.execute_callback(single_callback, result, win_id, all_tasks, config, effective_parent)
    end
    return
  end

  -- Handle string callback (task ID)
  if type(callback) == "string" then
    M.execute_task_callback(callback, result, win_id, all_tasks, config, parent_task_id)
  elseif type(callback) == "function" then
    M.execute_function_callback(callback, result)
  end
end

-- Execute a task callback (string callback)
---@param callback_task_id string The task ID to run as callback
---@param result table The task result information
---@param win_id number The window ID
---@param all_tasks table All tasks configuration
---@param config table The full configuration
---@param parent_task_id string|nil The ID of the task that triggered this callback
function M.execute_task_callback(callback_task_id, result, win_id, all_tasks, config, parent_task_id)
  -- Callback is a task ID - run that task
  local task_to_run = all_tasks[callback_task_id]

  -- If not found in all_tasks, check predefined tasks
  if not task_to_run then
    local predefined = require("smart-commit.predefined")
    local predefined_task = predefined.get(callback_task_id)
    if predefined_task then
      if debug_enabled then
        debug_module.log("Using predefined task '" .. callback_task_id .. "' as callback")
      end
      -- Create a copy of the predefined task
      task_to_run = vim.deepcopy(predefined_task)
      task_to_run.id = callback_task_id
      -- Add it to all_tasks so it can be referenced later
      all_tasks[callback_task_id] = task_to_run
    end
  end

  if task_to_run then
    -- Initialize the callback task if it doesn't exist in state
    if not state.get_task(callback_task_id) then
      if debug_enabled then
        debug_module.log(
          "Creating NEW callback task '" .. callback_task_id .. "' for parent '" .. (parent_task_id or "unknown") .. "'"
        )
      end
      state.initialize_task(callback_task_id, task_to_run, true, parent_task_id)
    else
      -- If task already exists, mark it as a callback (preserve existing state)
      if debug_enabled then
        debug_module.log(
          "Marking EXISTING task '"
            .. callback_task_id
            .. "' as callback for parent '"
            .. (parent_task_id or "unknown")
            .. "'"
        )
      end
      state.mark_as_callback(callback_task_id, parent_task_id)
    end

    -- Only run the callback task if it's not already running/completed
    if state.is_task_in_state(callback_task_id, state.TASK_STATE.PENDING) then
      vim.schedule(function()
        local executor = require("smart-commit.runner.executor")
        executor.run_task(win_id, task_to_run, all_tasks, config)
      end)
    end
  else
    vim.notify("Callback task not found: " .. callback_task_id, vim.log.levels.WARN)
  end
end

-- Execute a function callback
---@param callback_fn function The function to call as callback
---@param result table The task result information
function M.execute_function_callback(callback_fn, result)
  -- Callback is a function - call it with the result
  vim.schedule(function()
    local ok, err = pcall(callback_fn, result)
    if not ok then
      vim.notify("Callback function error: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

return M
