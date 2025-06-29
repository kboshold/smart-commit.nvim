-- Smart Commit Task Runner
-- Author: kboshold

local ui = require("smart-commit.ui")
local utils = require("smart-commit.utils")

---@class SmartCommitRunner
local M = {}

-- Task states
M.TASK_STATE = {
  PENDING = "pending",
  WAITING = "waiting", -- New state for tasks waiting on dependencies
  RUNNING = "running",
  SUCCESS = "success",
  FAILED = "failed",
  SKIPPED = "skipped", -- New state for tasks that were skipped due to conditions
}

-- Current task state
---@type table<string, {state: string, output: string, start_time: number, end_time: number?}>
M.tasks = {}

-- Overall process timing
M.process_start_time = 0

-- Timer for UI updates
local update_timer = nil

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

  -- Initialize task state
  M.tasks[task.id] = {
    state = M.TASK_STATE.RUNNING,
    output = "",
    start_time = vim.loop.now(),
  }

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
      M.tasks[task.id].state = result and M.TASK_STATE.SUCCESS or M.TASK_STATE.FAILED
      M.tasks[task.id].end_time = vim.loop.now()
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
    if type(result) == "boolean" then
      M.tasks[task.id].state = result and M.TASK_STATE.SUCCESS or M.TASK_STATE.FAILED
    elseif type(result) == "table" and result.ok ~= nil then
      M.tasks[task.id].state = result.ok and M.TASK_STATE.SUCCESS or M.TASK_STATE.FAILED
    else
      M.tasks[task.id].state = M.TASK_STATE.FAILED
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
    M.tasks[task.id].state = M.TASK_STATE.SUCCESS
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
    M.tasks[task.id].state = M.TASK_STATE.SUCCESS
    vim.schedule(function()
      M.update_ui(win_id, all_tasks, config)
      M.update_signs(win_id)
    end)
    return
  elseif cmd == "exit 1" then
    M.tasks[task.id].state = M.TASK_STATE.FAILED
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
    end
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
  vim.system(cmd_parts, options, function(obj)
    -- Update task state based on exit code and set end_time
    M.tasks[task.id].end_time = vim.loop.now()

    if obj.code == 0 then
      M.tasks[task.id].state = M.TASK_STATE.SUCCESS
    else
      M.tasks[task.id].state = M.TASK_STATE.FAILED
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
    elseif task.state == M.TASK_STATE.FAILED then
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
    -- Check if any task failed
    local any_failed = false
    for _, task in pairs(M.tasks) do
      if task.state == M.TASK_STATE.FAILED then
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
        { text = utils.ICONS.ERROR .. " Some tasks failed" .. elapsed_text, highlight_group = "DiagnosticError" },
      })
    else
      table.insert(content, {
        { text = "Status: ", highlight_group = "Label" },
        { text = utils.ICONS.SUCCESS .. " All tasks completed" .. elapsed_text, highlight_group = "DiagnosticOk" },
      })
    end
  end

  -- Get task keys and sort them
  local task_keys = {}
  for id, _ in pairs(M.tasks) do
    table.insert(task_keys, id)
  end
  table.sort(task_keys)

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
    if task_state.state == M.TASK_STATE.SKIPPED and config and config.defaults and config.defaults.hide_skipped then
      goto continue
    end

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
      status_text = "⏳ Waiting for dependencies..."
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
      status_text = " Skipped"
      status_hl = "Comment"
    else
      status_text = "󰔟 Pending"
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

    table.insert(content, {
      { text = border_char .. " ", highlight_group = "Comment" },
      { text = display_text .. " ", highlight_group = "Identifier" },
      { text = status_text, highlight_group = status_hl },
    })

    ::continue::
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
      M.tasks[id] = {
        state = M.TASK_STATE.PENDING,
        output = "",
        start_time = 0,
        depends_on = task.depends_on or {},
      }
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

return M
