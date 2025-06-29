-- Smart Commit Utilities
-- Author: kboshold

---@class SmartCommitUtils
local M = {}

-- Spinner frames for animation - Braille patterns
---@type string[]
M.spinner_frames = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}
M.current_spinner_idx = 1

-- Get the current spinner frame without advancing
---@return string The current spinner frame
function M.get_current_spinner_frame()
  return M.spinner_frames[M.current_spinner_idx]
end

-- Advance to the next spinner frame and return it
---@return string The next spinner frame
function M.advance_spinner_frame()
  local frame = M.spinner_frames[M.current_spinner_idx]
  M.current_spinner_idx = (M.current_spinner_idx % #M.spinner_frames) + 1
  return frame
end

-- Define sign icons
---@type table<string, string>
M.ICONS = {
  RUNNING = "󱑢", -- Spinner icon
  SUCCESS = "✓", -- Check mark
  ERROR = "✗", -- X mark
  WARNING = "⚠", -- Warning
  INFO = "ℹ", -- Info
}

-- Border icons for UI
---@type table<string, string>
M.BORDERS = {
  TOP = "┌",
  MIDDLE = "├",
  BOTTOM = "└",
  VERTICAL = "│",
  HORIZONTAL = "─",
}

return M
