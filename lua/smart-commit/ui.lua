-- Smart Commit UI Components
-- Author: kboshold

---@class SmartCommitUI
local M = {}

-- Internal state tracking for header windows
---@type table<number, StickyHeaderState>
local header_states = {}

-- Internal state tracking for analysis windows
---@type table<number, {win_id: number, buf_id: number, is_visible: boolean}>
local analysis_windows = {}

--- Creates a split window for analysis results on the right side of the commit buffer
---@param target_win_id number The window ID of the commit buffer
---@param title string The title for the analysis window
---@param content string The content to display in the analysis window
---@return number|nil The window ID of the created split window, or nil if creation failed
function M.show_analysis(target_win_id, title, content)
  -- Check if the target window is valid
  if not vim.api.nvim_win_is_valid(target_win_id) then
    return nil
  end

  -- Close existing analysis window if it exists
  if analysis_windows[target_win_id] and analysis_windows[target_win_id].is_visible then
    if vim.api.nvim_win_is_valid(analysis_windows[target_win_id].win_id) then
      vim.api.nvim_win_close(analysis_windows[target_win_id].win_id, true)
    end
  end

  -- Save current window and position
  local current_win = vim.api.nvim_get_current_win()
  local current_view = vim.fn.winsaveview()

  -- Focus the target window
  vim.api.nvim_set_current_win(target_win_id)

  -- Create a new buffer for the analysis
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf_id, "swapfile", false)
  vim.api.nvim_buf_set_option(buf_id, "filetype", "markdown")
  vim.api.nvim_buf_set_name(buf_id, "SmartCommit-Analysis")

  -- Set the content
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Create a vertical split on the right
  vim.cmd("vertical botright 60vsplit")
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
  local ns_id = vim.api.nvim_create_namespace("smart_commit_analysis_title")
  vim.api.nvim_buf_set_lines(buf_id, 0, 0, false, { "", "" })
  vim.api.nvim_buf_set_extmark(buf_id, ns_id, 0, 0, {
    virt_text = { { " " .. title .. " ", "Title" } },
    virt_text_pos = "overlay",
  })

  -- Store the window state
  analysis_windows[target_win_id] = {
    win_id = win_id,
    buf_id = buf_id,
    is_visible = true,
  }

  -- Return to the original window and restore view
  vim.api.nvim_set_current_win(current_win)
  vim.fn.winrestview(current_view)

  -- Add autocmd to close the analysis window when the target window is closed
  local augroup = vim.api.nvim_create_augroup("SmartCommitAnalysis", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(target_win_id),
    callback = function()
      if analysis_windows[target_win_id] and analysis_windows[target_win_id].is_visible then
        if vim.api.nvim_win_is_valid(analysis_windows[target_win_id].win_id) then
          vim.api.nvim_win_close(analysis_windows[target_win_id].win_id, true)
        end
        analysis_windows[target_win_id].is_visible = false
      end
    end,
    once = true,
  })

  return win_id
end

--- Closes the analysis window for a given target window
---@param target_win_id number The window ID of the commit buffer
function M.close_analysis(target_win_id)
  if analysis_windows[target_win_id] and analysis_windows[target_win_id].is_visible then
    if vim.api.nvim_win_is_valid(analysis_windows[target_win_id].win_id) then
      vim.api.nvim_win_close(analysis_windows[target_win_id].win_id, true)
    end
    analysis_windows[target_win_id].is_visible = false
  end
end

-- Setup autocommands for window management
local function setup_window_autocommands()
  local augroup = vim.api.nvim_create_augroup("SmartCommitUI", { clear = true })

  -- Close header window when target buffer is closed
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = augroup,
    pattern = "COMMIT_EDITMSG",
    callback = function(args)
      -- Find and close any associated header windows
      for target_win_id, state in pairs(header_states) do
        if state.is_visible and vim.api.nvim_win_is_valid(state.header_win_id) then
          vim.api.nvim_win_close(state.header_win_id, true)
          state.is_visible = false
        end
      end
    end,
    desc = "Close Smart Commit header when commit buffer is closed",
  })

  -- Handle :q in commit buffer to close both windows
  vim.api.nvim_create_autocmd("QuitPre", {
    group = augroup,
    pattern = "COMMIT_EDITMSG",
    callback = function(args)
      local current_win = vim.api.nvim_get_current_win()
      local state = header_states[current_win]

      if state and state.is_visible and vim.api.nvim_win_is_valid(state.header_win_id) then
        -- Close the header window first
        vim.api.nvim_win_close(state.header_win_id, true)
        state.is_visible = false

        -- Schedule the buffer close to happen after this autocmd
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_win_close(current_win, true)
          end
        end)

        -- Prevent the default :q behavior since we're handling it
        return true
      end
    end,
    desc = "Handle :q in commit buffer to close both windows",
  })
end

-- Initialize autocommands
setup_window_autocommands()

--- Gets the current content for a given window.
---@param target_win_id number The window to get content for.
---@return StickyHeaderContent The current content or empty table if not found.
function M.get_current_content(target_win_id)
  local state = header_states[target_win_id]
  if state and state.current_content then
    return state.current_content
  end
  return {}
end

--- Sets or updates the header content for a given window.
--- Creates the header if it doesn't exist.
---@param target_win_id number The window to attach the header to.
---@param content StickyHeaderContent The content to display.
function M.set(target_win_id, content)
  -- Ensure the target window exists
  if not vim.api.nvim_win_is_valid(target_win_id) then
    return
  end

  -- Store the content for later reference (needed for debug window)
  if not header_states[target_win_id] then
    header_states[target_win_id] = {}
  end
  header_states[target_win_id].current_content = content

  -- Always show the status window at the bottom
  local state = header_states[target_win_id]
  if
    not state
    or not state.is_visible
    or not state.header_win_id
    or not vim.api.nvim_win_is_valid(state.header_win_id or 0)
  then
    state = M._create_header(target_win_id)
    header_states[target_win_id] = state
  end

  -- Update the content
  M._update_content(state, content)

  -- If debug mode is enabled, also update the debug window
  local debug = require("smart-commit.debug")
  if debug.is_enabled() then
    -- Use pcall to handle potential errors in fast event context
    pcall(function()
      debug.update(target_win_id, content)
    end)
  end
end

--- Toggles the header's visibility for a given window.
---@param target_win_id number The window where the header is attached.
---@param content StickyHeaderContent The content to display if showing the header.
function M.toggle(target_win_id, content)
  local state = header_states[target_win_id]

  if state and state.is_visible and vim.api.nvim_win_is_valid(state.header_win_id) then
    -- Hide the header
    vim.api.nvim_win_close(state.header_win_id, true)
    state.is_visible = false
  else
    -- Show the header
    M.set(target_win_id, content)
  end
end

--- Creates a new header window for the target window.
---@param target_win_id number The window to attach the header to.
---@return StickyHeaderState The newly created header state.
function M._create_header(target_win_id)
  -- Save current window and position
  local current_win = vim.api.nvim_get_current_win()
  local current_view = vim.fn.winsaveview()

  -- Focus the target window
  vim.api.nvim_set_current_win(target_win_id)

  -- Get target window options to match spacing
  local target_foldcolumn = vim.api.nvim_win_get_option(target_win_id, "foldcolumn")

  -- Create a new buffer for the header
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf_id, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(buf_id, "swapfile", false)
  vim.api.nvim_buf_set_option(buf_id, "filetype", "smartcommit")
  vim.api.nvim_buf_set_name(buf_id, "SmartCommit-Header")

  -- Create a split at the bottom with minimal height
  vim.cmd("botright 1split")
  local win_id = vim.api.nvim_get_current_win()

  -- Set the buffer for the new window
  vim.api.nvim_win_set_buf(win_id, buf_id)

  -- Configure window options - use explicit signcolumn width for indentation
  vim.api.nvim_win_set_option(win_id, "wrap", false)
  vim.api.nvim_win_set_option(win_id, "number", false)
  vim.api.nvim_win_set_option(win_id, "relativenumber", false)
  vim.api.nvim_win_set_option(win_id, "cursorline", false)
  vim.api.nvim_win_set_option(win_id, "signcolumn", "yes:4")
  vim.api.nvim_win_set_option(win_id, "foldcolumn", target_foldcolumn)
  vim.api.nvim_win_set_option(win_id, "winfixheight", true)

  -- Return to the original window and restore view
  vim.api.nvim_set_current_win(current_win)
  vim.fn.winrestview(current_view)

  -- Return the new state
  return {
    header_win_id = win_id,
    header_buf_id = buf_id,
    target_win_id = target_win_id,
    is_visible = true,
  }
end

--- Updates the content of the header window.
---@param state StickyHeaderState The header state to update.
---@param content StickyHeaderContent The content to display.
function M._update_content(state, content)
  if not vim.api.nvim_buf_is_valid(state.header_buf_id) then
    return
  end

  -- Convert content to lines of text with highlights
  local lines = {}
  local highlights = {}

  for i, line in ipairs(content) do
    local line_text = ""
    local line_highlights = {}

    for j, chunk in ipairs(line) do
      local start_col = #line_text
      line_text = line_text .. chunk.text
      table.insert(line_highlights, {
        hlgroup = chunk.highlight_group,
        start_col = start_col,
        end_col = #line_text,
      })
    end

    table.insert(lines, line_text)
    highlights[i] = line_highlights
  end

  -- Set the lines in the buffer
  vim.api.nvim_buf_set_option(state.header_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.header_buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.header_buf_id, "modifiable", false)

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(state.header_buf_id, -1, 0, -1)
  local ns_id = vim.api.nvim_create_namespace("smart_commit_header")

  for line_num, line_highlights in pairs(highlights) do
    for _, hl in ipairs(line_highlights) do
      vim.api.nvim_buf_add_highlight(state.header_buf_id, ns_id, hl.hlgroup, line_num - 1, hl.start_col, hl.end_col)
    end
  end

  -- Resize the window to fit the content
  local height = #lines > 0 and #lines or 1
  vim.api.nvim_win_set_height(state.header_win_id, height)
end

return M
