-- Smart Commit Task Runner - Dependency Management
-- Author: kboshold

local debug_module = require("smart-commit.debug")
local state = require("smart-commit.runner.state")

-- Cache debug flag to avoid accessing vim.env in fast event contexts
local debug_enabled = vim.env.SMART_COMMIT_DEBUG == "1"

---@class SmartCommitRunnerDependencies
local M = {}

-- Initialize all tasks in the state
---@param tasks table<string, SmartCommitTask|false> The tasks to initialize
function M.initialize_tasks(tasks)
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
      state.initialize_task(id, task, false, nil)
    end
  end
end

-- Process task conditions and mark tasks as skipped if needed
---@param tasks table<string, SmartCommitTask|false> The tasks to process
function M.process_task_conditions(tasks)
  -- First pass: check 'when' conditions and mark tasks as skipped if needed
  for id, task in pairs(tasks) do
    if task and task.when and type(task.when) == "function" then
      local should_run = task.when()
      if not should_run then
        local task_state = state.get_task(id)
        if task_state then
          task_state.state = state.TASK_STATE.SKIPPED
        end
        if debug_enabled then
          debug_module.log("Task '" .. id .. "' skipped due to 'when' condition returning false")
        end
      end
    end
  end
end

-- Mark tasks with dependencies as waiting
function M.mark_waiting_tasks()
  -- Second pass: mark tasks with dependencies as waiting
  for id, task_state in pairs(state.tasks) do
    if task_state.state == state.TASK_STATE.PENDING and #task_state.depends_on > 0 then
      task_state.state = state.TASK_STATE.WAITING
      if debug_enabled then
        debug_module.log("Task '" .. id .. "' waiting for dependencies: " .. table.concat(task_state.depends_on, ", "))
      end
    end
  end
end

-- Run tasks that are ready (no dependencies and not skipped)
---@param win_id number The window ID
---@param tasks table<string, SmartCommitTask|false> The tasks configuration
---@param config table The configuration
function M.run_ready_tasks(win_id, tasks, config)
  -- Third pass: run tasks without dependencies that aren't skipped
  for id, task in pairs(tasks) do
    if task and not task.depends_on and state.is_task_in_state(id, state.TASK_STATE.PENDING) then
      local executor = require("smart-commit.runner.executor")
      executor.run_task(win_id, task, tasks, config)
    end
  end
end

-- Start dependency checking timer
---@param win_id number The window ID
---@param tasks table<string, SmartCommitTask|false> The tasks configuration
---@param config table The configuration
function M.start_dependency_checking(win_id, tasks, config)
  -- Set up a timer to check for tasks that can be run
  local check_dependencies_timer = vim.loop.new_timer()
  check_dependencies_timer:start(500, 500, function()
    vim.schedule(function()
      local all_done = true
      local ran_something = false

      -- Check for tasks that can be run
      for id, task_state in pairs(state.tasks) do
        if task_state.state == state.TASK_STATE.WAITING then
          all_done = false

          -- Check if all dependencies are satisfied
          local can_run = M.check_dependencies_satisfied(task_state.depends_on)

          -- If all dependencies are satisfied, run the task
          if can_run then
            local executor = require("smart-commit.runner.executor")
            executor.run_task(win_id, tasks[id], tasks, config)
            ran_something = true
          end
        elseif task_state.state == state.TASK_STATE.PENDING or task_state.state == state.TASK_STATE.RUNNING then
          all_done = false
        end
      end

      -- If all tasks are done or we ran something, update the UI
      if all_done or ran_something then
        local ui_manager = require("smart-commit.runner.ui_manager")
        ui_manager.update_ui(win_id, tasks, config)
        ui_manager.update_signs(win_id)
      end

      -- If all tasks are done, stop the timer
      if all_done then
        check_dependencies_timer:stop()
        check_dependencies_timer:close()
      end
    end)
  end)
end

-- Check if all dependencies are satisfied for a task
---@param dependencies table<string> List of dependency task IDs
---@return boolean True if all dependencies are satisfied
function M.check_dependencies_satisfied(dependencies)
  for _, dep_id in ipairs(dependencies) do
    local dep_task = state.get_task(dep_id)
    if not dep_task or (dep_task.state ~= state.TASK_STATE.SUCCESS and dep_task.state ~= state.TASK_STATE.SKIPPED) then
      return false
    end
  end
  return true
end

return M
