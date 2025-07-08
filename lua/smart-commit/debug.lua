-- Smart Commit Debug Module
-- Author: kboshold

local M = {}

-- Internal state tracking for debug windows
---@type table<number, {win_id: number, buf_id: number, is_visible: boolean}>
local debug_windows = {}

-- Track the single debug window
local single_debug_window = nil

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

-- Log storage
local log_entries = {}
local max_log_entries = 1000 -- Maximum number of log entries to keep

-- Function to refresh debug flag (useful for runtime changes)
function M.refresh_debug_flag()
  debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"
end

-- Check if debug mode is enabled
function M.is_enabled()
  return debug_enabled
end

-- Ensure the debug window exists
---@param win_id number The window ID to attach the debug window to
local function ensure_debug_window(win_id)
  if
    not single_debug_window
    or not single_debug_window.is_visible
    or not vim.api.nvim_win_is_valid(single_debug_window.win_id or 0)
  then
    -- Create a new debug window with current logs
    local content = "# Smart Commit Log\n\n" .. M.get_logs()
    M.show_window(win_id, "Smart Commit Log", content)
  end
end

-- Log a message with timestamp
---@param message string The message to log
---@param level? string Optional log level (INFO, WARN, ERROR)
---@param is_output? boolean Whether this is command output that should be formatted with backticks
function M.log(message, level, is_output)
  level = level or "INFO"

  -- Get current timestamp
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")

  -- Format the log entry
  local entry
  if is_output then
    entry = string.format("### [%s] [%s] Command Output\n```\n%s\n```", timestamp, level, message)
  else
    entry = string.format("- **[%s] [%s]** %s", timestamp, level, message)
  end

  -- Add to log entries
  table.insert(log_entries, entry)

  -- Trim log if it gets too large
  if #log_entries > max_log_entries then
    table.remove(log_entries, 1)
  end

  -- If debug mode is enabled, update the debug window
  if debug_enabled then
    -- Use pcall to handle potential errors in fast event contexts
    pcall(function()
      -- Get the current window
      local current_win = vim.api.nvim_get_current_win()

      -- Ensure we have a debug window
      ensure_debug_window(current_win)

      -- If we have an active debug window, update it
      if
        single_debug_window
        and single_debug_window.is_visible
        and vim.api.nvim_win_is_valid(single_debug_window.win_id)
      then
        -- Schedule the update to avoid fast event context issues
        vim.schedule(function()
          -- Get all logs
          local content = "# Smart Commit Log\n\n" .. M.get_logs()

          -- Update the window content
          local buf_id = single_debug_window.buf_id
          if vim.api.nvim_buf_is_valid(buf_id) then
            local lines = vim.split(content, "\n")
            vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
            vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(buf_id, "modifiable", false)

            -- Scroll to the bottom
            vim.api.nvim_win_set_cursor(single_debug_window.win_id, { #lines, 0 })
          end
        end)
      end
    end)
  end
end

-- Get all log entries as a string
---@return string All log entries joined with newlines
function M.get_logs()
  return table.concat(log_entries, "\n")
end

-- Show the log window
---@param force? boolean Force show the window even if debug mode is disabled
function M.show_log_window(force)
  if not debug_enabled and not force then
    return
  end

  -- Get the current window
  local current_win = vim.api.nvim_get_current_win()

  -- Create log content
  local content = "# Smart Commit Log\n\n" .. M.get_logs()

  -- Show the window
  if
    single_debug_window
    and single_debug_window.is_visible
    and vim.api.nvim_win_is_valid(single_debug_window.win_id)
  then
    -- Update existing window
    M.update_window(current_win, content)
  else
    -- Create new window
    M.show_window(current_win, "Smart Commit Log", content)
  end

  -- Scroll to the bottom if window exists
  if
    single_debug_window
    and single_debug_window.is_visible
    and vim.api.nvim_win_is_valid(single_debug_window.win_id)
  then
    local lines = vim.split(content, "\n")
    vim.api.nvim_win_set_cursor(single_debug_window.win_id, { #lines, 0 })
  end
end

-- Collect all debug information into a single string
---@param content table The current header content
---@return string The combined debug information
function M.collect_information(content)
  local debug_content = "# Smart Commit Debug Information\n\n"

  -- Add task status information
  debug_content = debug_content .. "## Task Status\n"
  for _, line in ipairs(content) do
    local line_text = ""
    for _, chunk in ipairs(line) do
      line_text = line_text .. chunk.text
    end
    debug_content = debug_content .. line_text .. "\n"
  end

  -- Add configuration information
  debug_content = debug_content .. "\n## Configuration\n"
  local config = require("smart-commit").config
  if config then
    debug_content = debug_content .. "- **Auto Run**: " .. tostring(config.defaults.auto_run) .. "\n"
    debug_content = debug_content .. "- **Sign Column**: " .. tostring(config.defaults.sign_column) .. "\n"
    debug_content = debug_content .. "- **Hide Skipped**: " .. tostring(config.defaults.hide_skipped) .. "\n"

    -- List tasks
    debug_content = debug_content .. "\n### Configured Tasks\n"
    for id, task in pairs(config.tasks or {}) do
      if type(task) == "table" then
        debug_content = debug_content .. "- `" .. id .. "`"
        if task.label then
          debug_content = debug_content .. " (" .. task.label .. ")"
        end
        debug_content = debug_content .. "\n"
      end
    end
  end

  -- Add task details
  debug_content = debug_content .. "\n## Task Details\n"
  local runner = require("smart-commit.runner")
  for id, task in pairs(runner.tasks or {}) do
    debug_content = debug_content .. "### Task: `" .. id .. "`\n"
    debug_content = debug_content .. "- **State**: " .. (task.state or "unknown") .. "\n"

    -- Add timing information
    if task.start_time and task.start_time > 0 then
      local elapsed_ms = (task.end_time or vim.loop.now()) - task.start_time
      debug_content = debug_content .. "- **Time**: " .. string.format("%.2fs", elapsed_ms / 1000) .. "\n"
    end

    -- Add dependency information
    if task.depends_on and #task.depends_on > 0 then
      debug_content = debug_content .. "- **Dependencies**: " .. table.concat(task.depends_on, ", ") .. "\n"
    end

    -- Add callback information
    if task.is_callback then
      debug_content = debug_content .. "- **Callback of**: " .. (task.parent_task or "unknown") .. "\n"
    end

    -- Add output if available
    if task.output and task.output ~= "" then
      debug_content = debug_content .. "- **Output**:\n```\n" .. task.output .. "\n```\n"
    end

    debug_content = debug_content .. "\n"
  end

  return debug_content
end

-- Creates a split window for debug output on the right side of the commit buffer
---@param target_win_id number The window ID of the commit buffer
---@param title string The title for the debug window
---@param content string The content to display in the debug window
---@return number|nil The window ID of the created split window, or nil if creation failed
function M.show_window(target_win_id, title, content)
  -- Check if the target window is valid
  if not vim.api.nvim_win_is_valid(target_win_id) then
    return nil
  end

  -- Close existing debug window if it exists
  if single_debug_window and single_debug_window.is_visible then
    if vim.api.nvim_win_is_valid(single_debug_window.win_id) then
      vim.api.nvim_win_close(single_debug_window.win_id, true)
    end
    single_debug_window.is_visible = false
  end

  -- Save current window and position
  local current_win = vim.api.nvim_get_current_win()
  local current_view = vim.fn.winsaveview()

  -- Focus the target window
  vim.api.nvim_set_current_win(target_win_id)

  -- Create a new buffer for the debug output
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf_id, "swapfile", false)
  vim.api.nvim_buf_set_option(buf_id, "filetype", "markdown")
  vim.api.nvim_buf_set_name(buf_id, "SmartCommit-Debug")

  -- Set the content
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Create a vertical split on the right with a larger width (80 columns)
  vim.cmd("vertical botright 80vsplit")
  local win_id = vim.api.nvim_get_current_win()

  -- Set the buffer for the new window
  vim.api.nvim_win_set_buf(win_id, buf_id)

  -- Configure window options
  vim.api.nvim_win_set_option(win_id, "wrap", true)
  vim.api.nvim_win_set_option(win_id, "number", false)
  vim.api.nvim_win_set_option(win_id, "relativenumber", false)
  vim.api.nvim_win_set_option(win_id, "cursorline", false)
  vim.api.nvim_win_set_option(win_id, "signcolumn", "no")
  vim.api.nvim_win_set_option(win_id, "winfixwidth", true)

  -- Add a buffer title using extmarks
  local ns_id = vim.api.nvim_create_namespace("smart_commit_debug_title")
  vim.api.nvim_buf_set_lines(buf_id, 0, 0, false, { "", "" })
  vim.api.nvim_buf_set_extmark(buf_id, ns_id, 0, 0, {
    virt_text = { { " " .. title .. " ", "Title" } },
    virt_text_pos = "overlay",
  })

  -- Store the window state in the single debug window variable
  single_debug_window = {
    win_id = win_id,
    buf_id = buf_id,
    is_visible = true,
    target_win_id = target_win_id,
  }

  -- Also store in the debug_windows table for backward compatibility
  debug_windows[target_win_id] = single_debug_window

  -- Return to the original window and restore view
  vim.api.nvim_set_current_win(current_win)
  vim.fn.winrestview(current_view)

  -- Add autocmd to close the debug window when the target window is closed
  local augroup = vim.api.nvim_create_augroup("SmartCommitDebug", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(target_win_id),
    callback = function()
      if single_debug_window and single_debug_window.is_visible then
        if vim.api.nvim_win_is_valid(single_debug_window.win_id) then
          vim.api.nvim_win_close(single_debug_window.win_id, true)
        end
        single_debug_window.is_visible = false
      end
    end,
    once = true,
  })

  return win_id
end

-- Updates the content of the debug window
---@param target_win_id number The window ID of the commit buffer
---@param content string The new content to display
function M.update_window(target_win_id, content)
  if single_debug_window and single_debug_window.is_visible then
    local buf_id = single_debug_window.buf_id
    if vim.api.nvim_buf_is_valid(buf_id) then
      local lines = vim.split(content, "\n")
      vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
    end
  end
end

-- Update debug information for a given window
---@param win_id number The window ID
---@param content table The current header content
function M.update(win_id, content)
  if not debug_enabled then
    return
  end

  -- Schedule the UI update to avoid fast event context issues
  vim.schedule(function()
    local debug_content = M.collect_information(content)

    if
      single_debug_window
      and single_debug_window.is_visible
      and vim.api.nvim_win_is_valid(single_debug_window.win_id)
    then
      -- Update the existing debug window
      local buf_id = single_debug_window.buf_id
      if vim.api.nvim_buf_is_valid(buf_id) then
        local lines = vim.split(debug_content, "\n")
        vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
      end
    else
      -- Close any existing debug windows first
      for target_win_id, window_state in pairs(debug_windows) do
        if window_state.is_visible and vim.api.nvim_win_is_valid(window_state.win_id) then
          vim.api.nvim_win_close(window_state.win_id, true)
          window_state.is_visible = false
        end
      end

      -- Create a new debug window
      M.show_window(win_id, "Smart Commit Debug", debug_content)
    end
  end)
end

-- Close the debug window for a given target window
---@param target_win_id number The window ID of the commit buffer
function M.close_window(target_win_id)
  if single_debug_window and single_debug_window.is_visible then
    if vim.api.nvim_win_is_valid(single_debug_window.win_id) then
      vim.api.nvim_win_close(single_debug_window.win_id, true)
    end
    single_debug_window.is_visible = false
  end

  -- Also update the debug_windows table for backward compatibility
  if debug_windows[target_win_id] and debug_windows[target_win_id].is_visible then
    debug_windows[target_win_id].is_visible = false
  end
end

return M
