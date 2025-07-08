-- Smart Commit Task Runner - Main Module
-- Author: kboshold

local callbacks = require("smart-commit.runner.callbacks")
local dependencies = require("smart-commit.runner.dependencies")
local executor = require("smart-commit.runner.executor")
local processes = require("smart-commit.runner.processes")
local state = require("smart-commit.runner.state")
local timers = require("smart-commit.runner.timers")
local ui_manager = require("smart-commit.runner.ui_manager")

---@class SmartCommitRunner
local M = {}

-- Re-export task states for backward compatibility
M.TASK_STATE = state.TASK_STATE

-- Re-export task storage for backward compatibility
M.tasks = state.tasks

-- Process timing
M.process_start_time = 0

-- Initialize the runner
local function initialize()
  ui_manager.setup_signs()
end

-- Run a single task
---@param win_id number The window ID of the commit buffer
---@param task SmartCommitTask The task to run
---@param all_tasks table<string, SmartCommitTask|false>|nil All tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.run_task(win_id, task, all_tasks, config)
  executor.run_task(win_id, task, all_tasks, config)
end

-- Run tasks with dependency tracking
---@param win_id number The window ID of the commit buffer
---@param tasks table<string, SmartCommitTask|false> The tasks to run
---@param config SmartCommitConfig|nil The full configuration
function M.run_tasks_with_dependencies(win_id, tasks, config)
  -- Set the process start time
  M.process_start_time = vim.loop.now()

  -- Initialize all tasks and handle dependencies
  dependencies.initialize_tasks(tasks)

  -- Start UI updates
  timers.start_ui_updates(win_id, tasks, config)

  -- Process tasks based on conditions and dependencies
  dependencies.process_task_conditions(tasks)
  dependencies.mark_waiting_tasks()

  -- Update UI to show initial states
  ui_manager.update_ui(win_id, tasks, config)
  ui_manager.update_signs(win_id)

  -- Check if all tasks are already complete
  if state.all_tasks_complete() then
    timers.stop_ui_updates()
    return
  end

  -- Run tasks without dependencies
  dependencies.run_ready_tasks(win_id, tasks, config)

  -- Start dependency checking
  dependencies.start_dependency_checking(win_id, tasks, config)
end

-- Check if all tasks are complete
---@return boolean True if all tasks are complete
function M.all_tasks_complete()
  return state.all_tasks_complete()
end

-- Kill all active processes
function M.kill_all_tasks()
  processes.kill_all_tasks()
  timers.stop_ui_updates()
end

-- Update the UI with current task states
---@param win_id number The window ID of the commit buffer
---@param tasks table<string, SmartCommitTask|false>|nil The tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.update_ui(win_id, tasks, config)
  ui_manager.update_ui(win_id, tasks, config)
end

-- Update signs in the commit buffer
---@param win_id number The window ID of the commit buffer
function M.update_signs(win_id)
  ui_manager.update_signs(win_id)
end

-- Start periodic UI updates
---@param win_id number The window ID of the commit buffer
---@param tasks table<string, SmartCommitTask|false>|nil The tasks configuration
---@param config SmartCommitConfig|nil The full configuration
function M.start_ui_updates(win_id, tasks, config)
  timers.start_ui_updates(win_id, tasks, config)
end

-- Stop UI updates
function M.stop_ui_updates()
  timers.stop_ui_updates()
end

-- Initialize the runner
initialize()

return M
