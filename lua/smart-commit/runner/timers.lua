-- Smart Commit Task Runner - Timer Management
-- Author: kboshold

local state = require("smart-commit.runner.state")
local utils = require("smart-commit.utils")

---@class SmartCommitRunnerTimers
local M = {}

-- Timer for UI updates
local update_timer = nil

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
        local ui_manager = require("smart-commit.runner.ui_manager")
        ui_manager.update_ui(win_id, tasks, config)
        ui_manager.update_signs(win_id)

        -- Check if all tasks are complete and stop the timer if they are
        if state.all_tasks_complete() then
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

-- Check if UI updates are running
---@return boolean True if UI updates are active
function M.is_ui_updates_active()
  return update_timer ~= nil
end

return M
