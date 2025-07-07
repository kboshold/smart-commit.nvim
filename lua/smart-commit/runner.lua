-- Smart Commit Task Runner
-- Author: kboshold

local ui = require("smart-commit.ui")
local utils = require("smart-commit.utils")

---@class SmartCommitRunner
local M = {}

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

-- Function to refresh debug flag (useful for runtime changes)
local function refresh_debug_flag()
  debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"
end

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
local function safe_update_task_state(task_id, new_state)
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
        print(
          "Smart Commit: Preserving callback status for task '"
            .. task_id
            .. "' (parent: "
            .. tostring(old_parent)
            .. ")"
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

-- Execute a task callback (either run another task or call a function)
---@param callback string | function The callback to execute
---@param result table The task result information
---@param win_id number The window ID
---@param all_tasks table All tasks configuration
---@param config table The full configuration
---@param parent_task_id string|nil The ID of the task that triggered this callback
local function execute_callback(callback, result, win_id, all_tasks, config, parent_task_id)
  if type(callback) == "string" then
    -- Callback is a task ID - run that task
    local task_to_run = all_tasks[callback]

    -- If not found in all_tasks, check predefined tasks
    if not task_to_run then
      local predefined = require("smart-commit.predefined")
      local predefined_task = predefined.get(callback)
      if predefined_task then
        if debug_enabled then
          print("Smart Commit: Using predefined task '" .. callback .. "' as callback")
        end
        -- Create a copy of the predefined task
        task_to_run = vim.deepcopy(predefined_task)
        task_to_run.id = callback
        -- Add it to all_tasks so it can be referenced later
        all_tasks[callback] = task_to_run
      end
    end

    if task_to_run then
      -- Initialize the callback task if it doesn't exist in M.tasks
      if not M.tasks[callback] then
        if debug_enabled then
          print(
            "Smart Commit: Creating NEW callback task '"
              .. callback
              .. "' for parent '"
              .. (parent_task_id or "unknown")
              .. "'"
          )
        end
        M.tasks[callback] = {
          state = M.TASK_STATE.PENDING,
          output = "",
          start_time = 0,
          depends_on = task_to_run.depends_on or {},
          is_callback = true,
          parent_task = parent_task_id,
        }
      else
        -- If task already exists, mark it as a callback (preserve existing state)
        if debug_enabled then
          print(
            "Smart Commit: Marking EXISTING task '"
              .. callback
              .. "' as callback for parent '"
              .. (parent_task_id or "unknown")
              .. "'"
          )
          print(
            "Smart Commit: Task '" .. callback .. "' current is_callback: " .. tostring(M.tasks[callback].is_callback)
          )
        end
        M.tasks[callback].is_callback = true
        M.tasks[callback].parent_task = parent_task_id
        if debug_enabled then
          print(
            "Smart Commit: Task '" .. callback .. "' updated is_callback: " .. tostring(M.tasks[callback].is_callback)
          )
        end
      end

      -- Only run the callback task if it's not already running/completed
      if M.tasks[callback].state == M.TASK_STATE.PENDING then
        vim.schedule(function()
          M.run_task(win_id, task_to_run, all_tasks, config)
        end)
      end
    else
      vim.notify("Callback task not found: " .. callback, vim.log.levels.WARN)
    end
  elseif type(callback) == "function" then
    -- Callback is a function - call it with the result
    vim.schedule(function()
      local ok, err = pcall(callback, result)
      if not ok then
        vim.notify("Callback function error: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end
end

-- Overall process timing
M.process_start_time = 0

-- Timer for UI updates
local update_timer = nil

-- Store active processes for cleanup
---@type table<string, any>
local active_processes = {}

-- Define signs for the sign column
local function setup_signs()
  vim.fn.sign_define("SmartCommitRunning", { text = utils.ICONS.RUNNING, texthl = "DiagnosticInfo" })
  vim.fn.sign_define("SmartCommitSuccess", { text = utils.ICONS.SUCCESS, texthl = "DiagnosticOk" })
  vim.fn.sign_define("SmartCommitError", { text = utils.ICONS.ERROR, texthl = "DiagnosticError" })
  vim.fn.sign_define("SmartCommitWarning", { text = utils.ICONS.WARNING, texthl = "DiagnosticWarn" })

  -- Signs with count
  for i = 1, 9 do
    vim.fn.sign_define("SmartCommitError" .. i, { text = i .. utils.ICONS.ERROR, texthl = "DiagnosticError" })
    vim.fn.sign_define("SmartCommitSuccess" .. i, { text = i .. utils.ICONS.SUCCESS, texthl = "DiagnosticOk" })
  end
end

-- Initialize signs
setup_signs()

-- Run a simple task
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
  local existing_task = M.tasks[task.id]
  local existing_is_callback = existing_task and existing_task.is_callback
  local existing_parent_task = existing_task and existing_task.parent_task

  M.tasks[task.id] = {
    state = M.TASK_STATE.RUNNING,
    output = "",
    start_time = vim.loop.now(),
    is_callback = existing_is_callback or false,
    parent_task = existing_parent_task,
  }

  if debug_enabled and existing_is_callback then
    print(
      "Smart Commit: Preserving callback status for task '"
        .. task.id
        .. "' in run_task (parent: "
        .. tostring(existing_parent_task)
        .. ")"
    )
  end

  -- Start UI update timer if not already running
  M.start_ui_updates(win_id, all_tasks)

  -- Get the buffer ID for the commit buffer
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  -- Check if task has a handler (highest priority)
  if task.handler and type(task.handler) == "function" then
    -- Create context for the handler
    local ctx = {
      win_id = win_id,
      buf_id = buf_id,
      runner = M,
      task = task,
      config = config,
    }

    -- Run the handler
    local result = task.handler(ctx)

    -- Process the result
    if type(result) == "boolean" then
      -- Boolean result indicates success/failure
      -- Only update state if the task hasn't been aborted
      local state_updated = safe_update_task_state(task.id, result and M.TASK_STATE.SUCCESS or M.TASK_STATE.FAILED)
      if state_updated then
        M.tasks[task.id].end_time = vim.loop.now()

        -- Prepare result information for callbacks
        local task_result = {
          success = result,
          output = M.tasks[task.id].output,
        }

        -- Execute callbacks
        if result and task.on_success then
          if debug_enabled then
            print(
              "Smart Commit: Task '"
                .. task.id
                .. "' (handler) succeeded, executing on_success callback: "
                .. tostring(task.on_success)
            )
          end
          execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
        elseif not result and task.on_fail then
          if debug_enabled then
            print(
              "Smart Commit: Task '"
                .. task.id
                .. "' (handler) failed, executing on_fail callback: "
                .. tostring(task.on_fail)
            )
          end
          execute_callback(task.on_fail, task_result, win_id, all_tasks, config, task.id)
        end
      end
      vim.schedule(function()
        M.update_ui(win_id, all_tasks, config)
        M.update_signs(win_id)
      end)
    elseif type(result) == "string" then
      -- String result is a command to run
      M.run_command(win_id, buf_id, task, result, all_tasks, config)
    else
      -- Nil result means the handler is managing the task state asynchronously
      -- We'll just update the UI to show the running state
      vim.schedule(function()
        M.update_ui(win_id, all_tasks, config)
        M.update_signs(win_id)
      end)
    end
    return
  end

  -- Check if task has a function (second priority)
  if task.fn and type(task.fn) == "function" then
    local result = task.fn()

    -- Set end time
    M.tasks[task.id].end_time = vim.loop.now()

    -- Process the result
    -- Only update state if the task hasn't been aborted
    local success = false
    local state_updated = false

    if type(result) == "boolean" then
      success = result
      state_updated = safe_update_task_state(task.id, result and M.TASK_STATE.SUCCESS or M.TASK_STATE.FAILED)
    elseif type(result) == "table" and result.ok ~= nil then
      success = result.ok
      state_updated = safe_update_task_state(task.id, result.ok and M.TASK_STATE.SUCCESS or M.TASK_STATE.FAILED)
    else
      success = false
      state_updated = safe_update_task_state(task.id, M.TASK_STATE.FAILED)
    end

    -- Execute callbacks if state was updated
    if state_updated then
      local task_result = {
        success = success,
        output = M.tasks[task.id].output,
      }

      if type(result) == "table" then
        task_result.error_message = result.message
      end

      -- Execute callbacks
      if success and task.on_success then
        execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
      elseif not success and task.on_fail then
        execute_callback(task.on_fail, task_result, win_id, all_tasks, config, task.id)
      end
    end

    vim.schedule(function()
      M.update_ui(win_id, all_tasks)
      M.update_signs(win_id)
    end)
    return
  end

  -- Determine the command to run (lowest priority)
  local cmd
  if type(task.command) == "function" then
    -- If command is a function, call it with the task as argument
    cmd = task.command(task)
  else
    -- Otherwise use the command string directly
    cmd = task.command
  end

  -- If cmd is nil or empty, skip this task
  if not cmd or cmd == "" then
    vim.notify("Empty command for task: " .. task.id .. ", marking as success", vim.log.levels.WARN)
    -- Only update state if the task hasn't been aborted
    local state_updated = safe_update_task_state(task.id, M.TASK_STATE.SUCCESS)
    if state_updated then
      M.tasks[task.id].end_time = vim.loop.now()

      -- Execute success callback
      if task.on_success then
        local task_result = {
          success = true,
          output = M.tasks[task.id].output,
        }
        execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
      end
    end
    vim.schedule(function()
      M.update_ui(win_id, all_tasks)
      M.update_signs(win_id)
    end)
    return
  end

  -- Run the command
  M.run_command(win_id, buf_id, task, cmd, all_tasks, config)
end

-- Run a shell command for a task
---@param win_id number The window ID of the commit buffer
---@param buf_id number The buffer ID of the commit buffer
---@param task SmartCommitTask The task to run
---@param cmd string The command to run
---@param all_tasks table<string, SmartCommitTask|false>|nil All tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.run_command(win_id, buf_id, task, cmd, all_tasks, config)
  -- Handle special commands like "exit 0" or "exit 1"
  if cmd == "exit 0" then
    -- Only update state if the task hasn't been aborted
    local state_updated = safe_update_task_state(task.id, M.TASK_STATE.SUCCESS)
    if state_updated then
      M.tasks[task.id].end_time = vim.loop.now()

      -- Execute success callback
      if task.on_success then
        local task_result = {
          success = true,
          exit_code = 0,
          output = M.tasks[task.id].output,
        }
        execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
      end
    end
    vim.schedule(function()
      M.update_ui(win_id, all_tasks, config)
      M.update_signs(win_id)
    end)
    return
  elseif cmd == "exit 1" then
    -- Only update state if the task hasn't been aborted
    local state_updated = safe_update_task_state(task.id, M.TASK_STATE.FAILED)
    if state_updated then
      M.tasks[task.id].end_time = vim.loop.now()

      -- Execute failure callback
      if task.on_fail then
        local task_result = {
          success = false,
          exit_code = 1,
          output = M.tasks[task.id].output,
        }
        execute_callback(task.on_fail, task_result, win_id, all_tasks, config, task.id)
      end
    end
    vim.schedule(function()
      M.update_ui(win_id, all_tasks, config)
      M.update_signs(win_id)
    end)
    return
  end

  -- Split the command into parts for vim.system
  local cmd_parts = {}
  for part in cmd:gmatch("%S+") do
    table.insert(cmd_parts, part)
  end

  -- Prepare options for vim.system
  local options = {
    stdout = function(err, data)
      if data then
        M.tasks[task.id].output = M.tasks[task.id].output .. data
      end
    end,
    stderr = function(err, data)
      if data then
        M.tasks[task.id].output = M.tasks[task.id].output .. data
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

  -- Run the task asynchronously
  local process = vim.system(cmd_parts, options, function(obj)
    -- Remove from active processes
    active_processes[task.id] = nil

    -- Update task state based on exit code and set end_time
    M.tasks[task.id].end_time = vim.loop.now()

    -- Prepare result information for callbacks
    local task_result = {
      success = obj.code == 0,
      exit_code = obj.code,
      output = M.tasks[task.id].output,
      stdout = obj.stdout or "",
      stderr = obj.stderr or "",
    }

    -- Only update state if the task hasn't been aborted
    local state_updated = false
    if obj.code == 0 then
      state_updated = safe_update_task_state(task.id, M.TASK_STATE.SUCCESS)
    else
      if debug_enabled then
        print("Smart Commit: Task '" .. task.id .. "' failed with exit code " .. obj.code)
        print("Smart Commit: Task '" .. task.id .. "' has on_fail: " .. tostring(task.on_fail))
        print("Smart Commit: Task '" .. task.id .. "' has on_success: " .. tostring(task.on_success))
      end
      state_updated = safe_update_task_state(task.id, M.TASK_STATE.FAILED)
    end

    -- Execute callbacks if state was updated (not aborted)
    if state_updated then
      if task_result.success and task.on_success then
        if debug_enabled then
          print(
            "Smart Commit: Task '"
              .. task.id
              .. "' succeeded, executing on_success callback: "
              .. tostring(task.on_success)
          )
        end
        execute_callback(task.on_success, task_result, win_id, all_tasks, config, task.id)
      elseif not task_result.success and task.on_fail then
        if debug_enabled then
          print("Smart Commit: Task '" .. task.id .. "' failed, executing on_fail callback: " .. tostring(task.on_fail))
        end
        execute_callback(task.on_fail, task_result, win_id, all_tasks, config, task.id)
      end
    end

    -- Update UI with the final state
    vim.schedule(function()
      M.update_ui(win_id, all_tasks, config)
      M.update_signs(win_id)

      -- Stop timer if all tasks are complete
      if M.all_tasks_complete() then
        M.stop_ui_updates()
      end
    end)
  end)

  -- Store the process handle for potential cleanup
  active_processes[task.id] = process

  -- Update signs immediately
  M.update_signs(win_id)
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

-- Start periodic UI updates
---@param win_id number The window ID of the commit buffer
---@param tasks table<string, SmartCommitTask|false>|nil The tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.start_ui_updates(win_id, tasks, config)
  if update_timer then
    return
  end

  update_timer = vim.loop.new_timer()
  update_timer:start(0, 100, function() -- Changed to 100ms for faster animation
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win_id) then
        -- Advance the spinner frame once per update cycle
        utils.advance_spinner_frame()

        -- Update UI and signs
        M.update_ui(win_id, tasks, config)
        M.update_signs(win_id)

        -- Check if all tasks are complete and stop the timer if they are
        if M.all_tasks_complete() then
          M.stop_ui_updates()
        end
      else
        M.stop_ui_updates()
      end
    end)
  end)
end

-- Stop UI updates
function M.stop_ui_updates()
  if update_timer then
    update_timer:stop()
    update_timer:close()
    update_timer = nil
  end
end

-- Update signs in the commit buffer
---@param win_id number The window ID of the commit buffer
function M.update_signs(win_id)
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  -- Clear existing signs
  vim.fn.sign_unplace("SmartCommitSigns", { buffer = buf_id })

  -- Count tasks by state
  local running_count = 0
  local error_count = 0
  local success_count = 0

  for _, task in pairs(M.tasks) do
    if task.state == M.TASK_STATE.RUNNING then
      running_count = running_count + 1
    elseif task.state == M.TASK_STATE.FAILED or task.state == M.TASK_STATE.ABORTED then
      error_count = error_count + 1
    elseif task.state == M.TASK_STATE.SUCCESS then
      success_count = success_count + 1
    end
  end

  -- Place appropriate sign
  if running_count > 0 then
    -- Use the current spinner frame for the running sign
    vim.fn.sign_define("SmartCommitRunning", { text = utils.get_current_spinner_frame(), texthl = "DiagnosticInfo" })
    vim.fn.sign_place(0, "SmartCommitSigns", "SmartCommitRunning", buf_id, { lnum = 1 })
  elseif error_count > 0 then
    local sign_name = "SmartCommitError"
    if error_count > 1 and error_count <= 9 then
      sign_name = sign_name .. error_count
    end
    vim.fn.sign_place(0, "SmartCommitSigns", sign_name, buf_id, { lnum = 1 })
  elseif success_count > 0 then
    local sign_name = "SmartCommitSuccess"
    if success_count > 1 and success_count <= 9 then
      sign_name = sign_name .. success_count
    end
    vim.fn.sign_place(0, "SmartCommitSigns", sign_name, buf_id, { lnum = 1 })
  end

  -- Force a redraw to update the sign column immediately
  vim.cmd("redrawstatus")
  vim.cmd("redraw!")
end

-- Update the UI with current task states
---@param win_id number The window ID of the commit buffer
---@param tasks table<string, SmartCommitTask|false>|nil The tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.update_ui(win_id, tasks, config)
  tasks = tasks or {} -- Default to empty table if not provided
  config = config or {} -- Default to empty table if not provided
  -- Create header content based on task states
  ---@type StickyHeaderContent
  local content = {
    {
      { text = "Smart Commit ", highlight_group = "Title" },
      { text = "Tasks", highlight_group = "String" },
    },
  }

  -- Check if any task is running
  local any_running = false
  for _, task in pairs(M.tasks) do
    if task.state == M.TASK_STATE.RUNNING then
      any_running = true
      break
    end
  end

  -- Add status line with spinner if any task is running
  if any_running then
    -- Calculate elapsed time so far
    local elapsed_ms = M.process_start_time > 0 and vim.loop.now() - M.process_start_time or 0
    local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)

    table.insert(content, {
      { text = "Status: ", highlight_group = "Label" },
      {
        text = utils.get_current_spinner_frame() .. " Running tasks..." .. elapsed_text,
        highlight_group = "DiagnosticInfo",
      },
    })
  else
    -- Check if any task failed or was aborted
    local any_failed = false
    for _, task in pairs(M.tasks) do
      if task.state == M.TASK_STATE.FAILED or task.state == M.TASK_STATE.ABORTED then
        any_failed = true
        break
      end
    end

    -- Calculate total elapsed time
    local elapsed_ms = M.process_start_time > 0 and vim.loop.now() - M.process_start_time or 0
    local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)

    if any_failed then
      table.insert(content, {
        { text = "Status: ", highlight_group = "Label" },
        {
          text = utils.ICONS.ERROR .. " Some tasks failed" .. elapsed_text,
          highlight_group = "DiagnosticError",
        },
      })
    else
      table.insert(content, {
        { text = "Status: ", highlight_group = "Label" },
        {
          text = utils.ICONS.SUCCESS .. " All tasks completed" .. elapsed_text,
          highlight_group = "DiagnosticOk",
        },
      })
    end
  end

  -- Get task keys and sort them (with callback tasks after their parents)
  local task_keys = {}
  for id, _ in pairs(M.tasks) do
    table.insert(task_keys, id)
  end

  -- Create a hierarchical sort that places callback tasks immediately after their parents
  local function get_sort_key(task_id)
    local task = M.tasks[task_id]
    if task.is_callback == true and task.parent_task then
      -- For callback tasks, use parent's sort key + callback suffix
      return task.parent_task .. "_callback_" .. task_id
    else
      -- For regular tasks, use the task ID directly
      return task_id
    end
  end

  table.sort(task_keys, function(a, b)
    local sort_key_a = get_sort_key(a)
    local sort_key_b = get_sort_key(b)

    if debug_enabled then
      print(
        "Smart Commit: Sorting - '" .. a .. "' (key: " .. sort_key_a .. ") vs '" .. b .. "' (key: " .. sort_key_b .. ")"
      )
    end

    return sort_key_a < sort_key_b
  end)

  -- Add task status lines
  local task_count = #task_keys
  local visible_tasks = 0
  local total_visible_tasks = 0

  -- First count how many tasks will be visible
  if config and config.defaults and config.defaults.hide_skipped then
    for _, id in ipairs(task_keys) do
      local task_state = M.tasks[id]
      if task_state.state ~= M.TASK_STATE.SKIPPED then
        total_visible_tasks = total_visible_tasks + 1
      end
    end
  else
    total_visible_tasks = task_count
  end

  for i, id in ipairs(task_keys) do
    local task_state = M.tasks[id]

    -- Skip this task if it's skipped and hide_skipped is true
    if
      not (task_state.state == M.TASK_STATE.SKIPPED and config and config.defaults and config.defaults.hide_skipped)
    then
      visible_tasks = visible_tasks + 1
      local status_text = ""
      local status_hl = ""
      local border_char = utils.BORDERS.MIDDLE
      local task_config = tasks[id]
      local task_icon = task_config and task_config.icon or ""

      -- Use bottom border for the last visible task
      if visible_tasks == total_visible_tasks then
        border_char = utils.BORDERS.BOTTOM
      end

      if task_state.state == M.TASK_STATE.RUNNING then
        status_text = utils.get_current_spinner_frame() .. " Running..."
        status_hl = "DiagnosticInfo"
      elseif task_state.state == M.TASK_STATE.WAITING then
        status_text = utils.ICONS.WAITING .. " Waiting for dependencies..."
        status_hl = "DiagnosticHint"
      elseif task_state.state == M.TASK_STATE.SUCCESS then
        -- Calculate elapsed time for completed tasks
        local elapsed_ms = task_state.start_time > 0 and (task_state.end_time or vim.loop.now()) - task_state.start_time
          or 0
        local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)
        status_text = utils.ICONS.SUCCESS .. " Success" .. elapsed_text
        status_hl = "DiagnosticOk"
      elseif task_state.state == M.TASK_STATE.FAILED then
        -- Calculate elapsed time for failed tasks
        local elapsed_ms = task_state.start_time > 0 and (task_state.end_time or vim.loop.now()) - task_state.start_time
          or 0
        local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)
        status_text = utils.ICONS.ERROR .. " Failed" .. elapsed_text
        status_hl = "DiagnosticError"
      elseif task_state.state == M.TASK_STATE.SKIPPED then
        status_text = utils.ICONS.SKIPPED .. " Skipped"
        status_hl = "Comment"
      elseif task_state.state == M.TASK_STATE.ABORTED then
        -- Calculate elapsed time for aborted tasks
        local elapsed_ms = task_state.start_time > 0 and (task_state.end_time or vim.loop.now()) - task_state.start_time
          or 0
        local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)
        status_text = utils.ICONS.ABORTED .. " Aborted" .. elapsed_text
        status_hl = "DiagnosticWarn"
      else
        status_text = utils.ICONS.PENDING .. " Pending"
        status_hl = "Comment"
      end

      -- Use task label instead of ID if available
      local display_text = id
      local task_config = tasks[id]
      local task_icon = task_config and task_config.icon or ""
      local task_label = task_config and task_config.label or id

      -- Use icon + label if available, otherwise use ID
      if task_icon and task_icon ~= "" then
        display_text = task_icon .. " " .. task_label
      else
        display_text = task_label
      end

      -- Add indentation for callback tasks with vertical line connector
      local indent = ""
      local border_prefix = border_char
      local is_callback = task_state.is_callback == true -- Handle nil as false

      if is_callback then
        if debug_enabled then
          print(
            "Smart Commit: Indenting callback task '"
              .. id
              .. "' (parent: "
              .. (task_state.parent_task or "unknown")
              .. ")"
          )
        end
        -- For callback tasks, show vertical line connector + callback indicator
        border_prefix = utils.BORDERS.VERTICAL .. " └"
      else
        if debug_enabled then
          print("Smart Commit: Regular task '" .. id .. "' (is_callback: " .. tostring(task_state.is_callback) .. ")")
        end
      end

      table.insert(content, {
        { text = border_prefix .. " ", highlight_group = "Comment" },
        { text = indent .. display_text .. " ", highlight_group = is_callback and "DiagnosticHint" or "Identifier" },
        { text = status_text, highlight_group = status_hl },
      })
    end
  end

  -- Update the header
  ui.set(win_id, content)
end

-- Run tasks with dependency tracking
---@param win_id number The window ID of the commit buffer
---@param tasks table<string, SmartCommitTask|false> The tasks to run
---@param config SmartCommitConfig|nil The full configuration
function M.run_tasks_with_dependencies(win_id, tasks, config)
  -- Set the process start time
  M.process_start_time = vim.loop.now()

  -- Debug: Print the tasks that will be run
  local task_count = 0
  local task_ids = {}
  for id, task in pairs(tasks) do
    if task then
      task_count = task_count + 1
      table.insert(task_ids, id)
    end
  end

  -- Initialize all tasks as pending
  for id, task in pairs(tasks) do
    if task then -- Skip tasks that are set to false
      if debug_enabled then
        print("Smart Commit: Initializing regular task '" .. id .. "'")
      end
      -- Ensure we don't overwrite existing callback tasks
      if not M.tasks[id] then
        M.tasks[id] = {
          state = M.TASK_STATE.PENDING,
          output = "",
          start_time = 0,
          depends_on = task.depends_on or {},
          is_callback = false, -- Regular tasks are not callbacks
          parent_task = nil,
        }
      else
        -- If task already exists (e.g., callback task), preserve callback status
        local existing_is_callback = M.tasks[id].is_callback
        local existing_parent = M.tasks[id].parent_task
        if debug_enabled then
          print(
            "Smart Commit: Task '"
              .. id
              .. "' already exists, preserving callback status: "
              .. tostring(existing_is_callback)
          )
        end
        M.tasks[id].state = M.TASK_STATE.PENDING
        M.tasks[id].output = ""
        M.tasks[id].start_time = 0
        M.tasks[id].depends_on = task.depends_on or {}
        M.tasks[id].is_callback = existing_is_callback or false
        M.tasks[id].parent_task = existing_parent
      end
    end
  end

  -- Start UI update timer
  M.start_ui_updates(win_id, tasks, config)

  -- First pass: check 'when' conditions and mark tasks as skipped if needed
  for id, task in pairs(tasks) do
    if task and task.when and type(task.when) == "function" then
      local should_run = task.when()
      if not should_run then
        M.tasks[id].state = M.TASK_STATE.SKIPPED
      end
    end
  end

  -- Second pass: mark tasks with dependencies as waiting
  for id, task_state in pairs(M.tasks) do
    if task_state.state == M.TASK_STATE.PENDING and #task_state.depends_on > 0 then
      task_state.state = M.TASK_STATE.WAITING
    end
  end

  -- Update UI to show initial states
  M.update_ui(win_id, tasks, config)
  M.update_signs(win_id)

  -- Check if all tasks are already complete (e.g., all skipped)
  if M.all_tasks_complete() then
    M.stop_ui_updates()
    return
  end

  -- Third pass: run tasks without dependencies that aren't skipped
  for id, task in pairs(tasks) do
    if task and not task.depends_on and M.tasks[id].state == M.TASK_STATE.PENDING then
      M.run_task(win_id, task, tasks, config)
    end
  end

  -- Set up a timer to check for tasks that can be run
  local check_dependencies_timer = vim.loop.new_timer()
  check_dependencies_timer:start(500, 500, function()
    vim.schedule(function()
      local all_done = true
      local ran_something = false

      -- Check for tasks that can be run
      for id, task_state in pairs(M.tasks) do
        if task_state.state == M.TASK_STATE.WAITING then
          all_done = false

          -- Check if all dependencies are satisfied
          local can_run = true
          for _, dep_id in ipairs(task_state.depends_on) do
            if
              not M.tasks[dep_id]
              or (M.tasks[dep_id].state ~= M.TASK_STATE.SUCCESS and M.tasks[dep_id].state ~= M.TASK_STATE.SKIPPED)
            then
              can_run = false
              break
            end
          end

          -- If all dependencies are satisfied, run the task
          if can_run then
            M.run_task(win_id, tasks[id], tasks, config)
            ran_something = true
          end
        elseif task_state.state == M.TASK_STATE.PENDING or task_state.state == M.TASK_STATE.RUNNING then
          all_done = false
        end
      end

      -- If all tasks are done or we ran something, update the UI
      if all_done or ran_something then
        M.update_ui(win_id, tasks, config)
        M.update_signs(win_id)
      end

      -- If all tasks are done, stop the timer
      if all_done then
        check_dependencies_timer:stop()
        check_dependencies_timer:close()
      end
    end)
  end)
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
      -- Note: This ABORTED state will be preserved by safe_update_task_state()
      -- to prevent async callbacks from overriding it
      if M.tasks[task_id] then
        M.tasks[task_id].state = M.TASK_STATE.ABORTED
        M.tasks[task_id].end_time = vim.loop.now()
        M.tasks[task_id].output = M.tasks[task_id].output .. "\n[Process aborted by user]"
      end
    end
  end

  -- Clear the active processes table
  active_processes = {}

  -- Stop UI updates
  M.stop_ui_updates()
end

return M
