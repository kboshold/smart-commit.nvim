-- Smart Commit Task Runner - UI Management
-- Author: kboshold

local debug_module = require("smart-commit.debug")
local state = require("smart-commit.runner.state")
local ui = require("smart-commit.ui")
local utils = require("smart-commit.utils")

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

---@class SmartCommitRunnerUIManager
local M = {}

-- Define signs for the sign column
function M.setup_signs()
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

  for _, task in pairs(state.tasks) do
    if task.state == state.TASK_STATE.RUNNING then
      running_count = running_count + 1
    elseif task.state == state.TASK_STATE.FAILED or task.state == state.TASK_STATE.ABORTED then
      error_count = error_count + 1
    elseif task.state == state.TASK_STATE.SUCCESS then
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

  -- Add status line
  M.add_status_line(content)

  -- Add task status lines
  M.add_task_lines(content, tasks, config)

  -- Update the header
  ui.set(win_id, content)
end

-- Add status line to content
---@param content table The content table to add to
function M.add_status_line(content)
  -- Count running tasks
  local running_count = 0
  for _, task in pairs(state.tasks) do
    if task.state == state.TASK_STATE.RUNNING then
      running_count = running_count + 1
    end
  end

  -- Get process start time from the main runner module
  local runner = require("smart-commit.runner")
  local process_start_time = runner.process_start_time or 0

  -- Add status line with spinner if any task is running
  if running_count > 0 then
    -- Calculate elapsed time so far
    local elapsed_ms = process_start_time > 0 and vim.loop.now() - process_start_time or 0
    local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)

    -- Create task count text
    local task_text = running_count == 1 and "task" or "tasks"
    local status_text = string.format("Running %d %s...%s", running_count, task_text, elapsed_text)

    table.insert(content, {
      { text = "Status: ", highlight_group = "Label" },
      {
        text = utils.get_current_spinner_frame() .. " " .. status_text,
        highlight_group = "DiagnosticInfo",
      },
    })
  else
    -- Check if any task failed or was aborted
    local any_failed = false
    for _, task in pairs(state.tasks) do
      if task.state == state.TASK_STATE.FAILED or task.state == state.TASK_STATE.ABORTED then
        any_failed = true
        break
      end
    end

    -- Calculate total elapsed time
    local elapsed_ms = process_start_time > 0 and vim.loop.now() - process_start_time or 0
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
end

-- Add task status lines to content
---@param content table The content table to add to
---@param tasks table The tasks configuration
---@param config table The configuration
function M.add_task_lines(content, tasks, config)
  -- Get task keys and sort them (with callback tasks after their parents)
  local task_keys = {}
  for id, _ in pairs(state.tasks) do
    table.insert(task_keys, id)
  end

  -- Create a hierarchical sort that places callback tasks immediately after their parents
  local function get_sort_key(task_id)
    local task = state.tasks[task_id]
    if task.is_callback == true and task.parent_task then
      -- For callback tasks, use parent's sort key + callback suffix
      -- This ensures proper nesting of callbacks
      local parent_task = state.tasks[task.parent_task]
      if parent_task and parent_task.is_callback then
        -- If parent is also a callback, get its sort key first to maintain hierarchy
        return get_sort_key(task.parent_task) .. "_callback_" .. task_id
      else
        -- Otherwise use simple parent + callback format
        return task.parent_task .. "_callback_" .. task_id
      end
    else
      -- For regular tasks, use the task ID directly
      return task_id
    end
  end

  table.sort(task_keys, function(a, b)
    local sort_key_a = get_sort_key(a)
    local sort_key_b = get_sort_key(b)

    if debug_enabled then
      debug_module.log(
        "Sorting - '" .. a .. "' (key: " .. sort_key_a .. ") vs '" .. b .. "' (key: " .. sort_key_b .. ")"
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
      local task_state = state.tasks[id]
      if task_state.state ~= state.TASK_STATE.SKIPPED then
        total_visible_tasks = total_visible_tasks + 1
      end
    end
  else
    total_visible_tasks = task_count
  end

  for i, id in ipairs(task_keys) do
    local task_state = state.tasks[id]

    -- Skip this task if it's skipped and hide_skipped is true
    if
      not (task_state.state == state.TASK_STATE.SKIPPED and config and config.defaults and config.defaults.hide_skipped)
    then
      visible_tasks = visible_tasks + 1
      M.add_single_task_line(content, id, task_state, tasks, visible_tasks == total_visible_tasks)
    end
  end
end

-- Add a single task line to content
---@param content table The content table to add to
---@param id string The task ID
---@param task_state table The task state
---@param tasks table The tasks configuration
---@param is_last boolean Whether this is the last visible task
function M.add_single_task_line(content, id, task_state, tasks, is_last)
  local status_text = ""
  local status_hl = ""
  local border_char = utils.BORDERS.MIDDLE
  local task_config = tasks[id]

  -- Use bottom border for the last visible task
  if is_last then
    border_char = utils.BORDERS.BOTTOM
  end

  -- Determine status text and highlight based on task state
  if task_state.state == state.TASK_STATE.RUNNING then
    status_text = utils.get_current_spinner_frame() .. " Running..."
    status_hl = "DiagnosticInfo"
  elseif task_state.state == state.TASK_STATE.WAITING then
    status_text = utils.ICONS.WAITING .. " Waiting for dependencies..."
    status_hl = "DiagnosticHint"
  elseif task_state.state == state.TASK_STATE.SUCCESS then
    -- Calculate elapsed time for completed tasks
    local elapsed_ms = task_state.start_time > 0 and (task_state.end_time or vim.loop.now()) - task_state.start_time
      or 0
    local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)
    status_text = utils.ICONS.SUCCESS .. " Success" .. elapsed_text
    status_hl = "DiagnosticOk"
  elseif task_state.state == state.TASK_STATE.FAILED then
    -- Calculate elapsed time for failed tasks
    local elapsed_ms = task_state.start_time > 0 and (task_state.end_time or vim.loop.now()) - task_state.start_time
      or 0
    local elapsed_text = string.format(" (%.2fs)", elapsed_ms / 1000)
    status_text = utils.ICONS.ERROR .. " Failed" .. elapsed_text
    status_hl = "DiagnosticError"
  elseif task_state.state == state.TASK_STATE.SKIPPED then
    status_text = utils.ICONS.SKIPPED .. " Skipped"
    status_hl = "Comment"
  elseif task_state.state == state.TASK_STATE.ABORTED then
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

  -- Calculate the nesting level for proper indentation
  local nesting_level = 0
  local current_task = task_state
  local parent_id = current_task.parent_task

  -- Traverse up the parent chain to determine nesting level
  while is_callback and parent_id do
    nesting_level = nesting_level + 1
    -- Get the parent task
    local parent_task = state.tasks[parent_id]
    if not parent_task then
      break
    end
    -- Move up to the next level
    parent_id = parent_task.parent_task
  end

  if is_callback then
    if debug_enabled then
      debug_module.log(
        "Indenting callback task '"
          .. id
          .. "' (parent: "
          .. (task_state.parent_task or "unknown")
          .. ", nesting level: "
          .. nesting_level
          .. ")"
      )
    end

    -- For callback tasks, add appropriate indentation based on nesting level
    if nesting_level > 1 then
      -- For nested callbacks (level 2+), add extra indentation
      indent = string.rep("  ", nesting_level - 1)
      border_prefix = utils.BORDERS.VERTICAL .. string.rep(" ", (nesting_level - 1) * 2) .. "└"
    else
      -- For first-level callbacks, use standard indentation
      border_prefix = utils.BORDERS.VERTICAL .. " └"
    end
  else
    if debug_enabled then
      debug_module.log("Regular task '" .. id .. "' (is_callback: " .. tostring(task_state.is_callback) .. ")")
    end
  end

  table.insert(content, {
    { text = border_prefix .. " ", highlight_group = "Comment" },
    { text = indent .. display_text .. " ", highlight_group = is_callback and "DiagnosticHint" or "Identifier" },
    { text = status_text, highlight_group = status_hl },
  })
end

return M
