-- Smart Commit Predefined Tasks
-- Author: kboshold

local pnpm = require("smart-commit.predefined.pnpm")
local copilot = require("smart-commit.predefined.copilot")

---@class PredefinedTasks
local M = {}

-- Collection of predefined tasks
---@type table<string, SmartCommitTask>
M.tasks = {
  -- Base PNPM task for extension
  ["pnpm"] = pnpm.base_task,

  -- Copilot tasks
  ["copilot:message"] = copilot.generate_commit_message,
  ["copilot:analyze"] = copilot.analyze_staged,
}

-- Get a predefined task by ID
---@param id string The task ID
---@return SmartCommitTask|nil The task or nil if not found
function M.get(id)
  local task = M.tasks[id]
  if not task then
    vim.notify("Predefined task not found: " .. id, vim.log.levels.WARN)
  end

  return task
end

-- Register a new predefined task
---@param id string The task ID
---@param task SmartCommitTask The task definition
function M.register(id, task)
  M.tasks[id] = task
end

return M
