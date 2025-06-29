# Creating Custom Tasks for Smart Commit

This guide provides detailed instructions and examples for creating custom tasks for the Smart Commit plugin.

## Task Types

Smart Commit supports several types of tasks, each with different capabilities:

1. **Command Tasks**: Execute shell commands
2. **Function Tasks**: Run Lua functions
3. **Handler Tasks**: Advanced tasks with full context access
4. **Extended Tasks**: Tasks that build upon predefined tasks

## Basic Task Structure

All tasks share a common structure:

```lua
{
  id = "unique-id",            -- Required: Unique identifier for the task
  label = "Human Label",       -- Required: User-friendly name shown in the UI
  icon = "󰉁",                 -- Optional: Icon to display (Nerd Font recommended)
  when = function() ... end,   -- Optional: Condition function to determine if task should run
  depends_on = { "task-id" },  -- Optional: List of task IDs that must complete first
  timeout = 30000,             -- Optional: Timeout in milliseconds (default: 30000)
  cwd = "/path/to/dir",        -- Optional: Working directory for this task
  env = { KEY = "value" },     -- Optional: Environment variables
}
```

## Command Tasks

Command tasks execute shell commands and are the simplest type of task:

```lua
["lint"] = {
  id = "lint",
  label = "Lint Code",
  icon = "󰉁",
  command = "eslint .",  -- Static command
}
```

You can also use a function to generate the command dynamically:

```lua
["dynamic-lint"] = {
  id = "dynamic-lint",
  label = "Dynamic Lint",
  command = function(task)
    local files = vim.fn.system("git diff --staged --name-only | grep '\\.js$'")
    if files == "" then
      return "echo 'No JS files to lint'"
    else
      return "eslint " .. files
    end
  end,
}
```

## Function Tasks

Function tasks execute Lua functions and return a boolean result:

```lua
["check-syntax"] = {
  id = "check-syntax",
  label = "Check Syntax",
  fn = function()
    -- Do some work
    local success = true
    
    -- Return true for success, false for failure
    return success
  end,
}
```

You can also return a table with additional information:

```lua
["validate"] = {
  id = "validate",
  label = "Validate",
  fn = function()
    -- Do some work
    
    return {
      ok = true,       -- Required: true for success, false for failure
      message = "Validation passed with 3 warnings"  -- Optional: Additional info
    }
  end,
}
```

## Handler Tasks

Handler tasks provide full access to the task context and offer the most flexibility:

```lua
["advanced-task"] = {
  id = "advanced-task",
  label = "Advanced Task",
  handler = function(ctx)
    -- Access context
    local win_id = ctx.win_id       -- Window ID of the commit buffer
    local buf_id = ctx.buf_id       -- Buffer ID of the commit buffer
    local runner = ctx.runner       -- Reference to the runner module
    local task = ctx.task           -- The task configuration
    local config = ctx.config       -- The full plugin configuration
    
    -- Option 1: Return a boolean for immediate success/failure
    return true  -- or false
    
    -- Option 2: Return a string to execute as a shell command
    return "git diff --staged | wc -l"
    
    -- Option 3: Return nil and manage the task state manually
    vim.schedule(function()
      -- Do some asynchronous work
      
      -- Update task state
      runner.tasks[task.id].state = runner.TASK_STATE.SUCCESS
      runner.tasks[task.id].end_time = vim.loop.now()
      runner.tasks[task.id].output = "Task completed successfully"
      
      -- Update UI
      runner.update_ui(win_id, nil, config)
      runner.update_signs(win_id)
    end)
    
    return nil  -- Indicates manual state management
  end,
}
```

## Extended Tasks

Extended tasks build upon predefined tasks:

```lua
["custom-lint"] = {
  extend = "pnpm",       -- ID of the predefined task to extend
  script = "lint",       -- Additional properties specific to the base task
  label = "Custom Lint", -- Override properties from the base task
}
```

## Conditional Execution

Use the `when` function to conditionally run tasks:

```lua
["conditional-task"] = {
  id = "conditional-task",
  label = "Conditional Task",
  command = "echo 'Running conditional task'",
  when = function()
    -- Check if any JavaScript files are staged
    local result = vim.fn.system("git diff --staged --name-only | grep '\\.js$'")
    return result ~= ""
  end,
}
```

## Task Dependencies

Use `depends_on` to specify task dependencies:

```lua
["build"] = {
  id = "build",
  label = "Build",
  command = "npm run build",
  depends_on = { "lint", "test" },  -- Will only run after lint and test succeed
}
```

## Real-World Examples

### 1. Check for Debugging Statements

```lua
["check-debug"] = {
  id = "check-debug",
  label = "Check Debug Statements",
  icon = "󰃤",
  handler = function(ctx)
    local result = vim.fn.system("git diff --staged | grep -E 'console\\.log|debugger'")
    
    if result ~= "" then
      -- Found debugging statements
      ctx.runner.tasks[ctx.task.id].output = "Found debugging statements:\n" .. result
      ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
      ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
      
      -- Show the results in an analysis window
      vim.schedule(function()
        local ui = require("smart-commit.ui")
        ui.show_analysis(ctx.win_id, "Debug Statements Found", 
          "The following debugging statements were found in staged code:\n\n```\n" .. result .. "\n```\n\nPlease remove them before committing.")
        
        ctx.runner.update_ui(ctx.win_id, nil, ctx.config)
        ctx.runner.update_signs(ctx.win_id)
      end)
      
      return nil
    else
      -- No debugging statements found
      return true
    end
  end,
}
```

### 2. Run Tests Only on Changed Files

```lua
["test-changed"] = {
  id = "test-changed",
  label = "Test Changed Files",
  icon = "󰙨",
  command = function(task)
    -- Get list of changed test files
    local changed_tests = vim.fn.system("git diff --staged --name-only | grep '_test\\.js$'")
    
    if changed_tests == "" then
      -- No test files changed
      return "echo 'No test files changed'"
    else
      -- Run tests only for changed files
      return "jest " .. changed_tests:gsub("\n", " ")
    end
  end,
}
```

### 3. Check Commit Message Quality

```lua
["check-commit-msg"] = {
  id = "check-commit-msg",
  label = "Check Commit Message",
  icon = "󰊄",
  handler = function(ctx)
    -- Wait a bit to ensure the commit message is written
    vim.defer_fn(function()
      -- Get the commit message from the buffer
      local lines = vim.api.nvim_buf_get_lines(ctx.buf_id, 0, -1, false)
      local msg = table.concat(lines, "\n")
      
      -- Check for common issues
      local issues = {}
      
      -- Check subject line length
      local subject = lines[1] or ""
      if #subject > 72 then
        table.insert(issues, "Subject line is too long (" .. #subject .. " > 72 characters)")
      end
      
      -- Check for imperative mood
      local first_word = subject:match("^%s*([%w]+)")
      if first_word then
        local non_imperative = {
          ["added"] = "add",
          ["fixed"] = "fix",
          ["updated"] = "update",
          ["removed"] = "remove",
          ["changed"] = "change",
          ["implemented"] = "implement"
        }
        
        if non_imperative[first_word:lower()] then
          table.insert(issues, "Use imperative mood in subject line ('" .. 
            non_imperative[first_word:lower()] .. "' instead of '" .. first_word .. "')")
        end
      end
      
      -- Update task state based on issues
      if #issues > 0 then
        ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
        ctx.runner.tasks[ctx.task.id].output = table.concat(issues, "\n")
        
        -- Show analysis window with suggestions
        local ui = require("smart-commit.ui")
        ui.show_analysis(ctx.win_id, "Commit Message Issues", 
          "# Commit Message Issues\n\n" .. table.concat(issues, "\n- "))
      else
        ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.SUCCESS
        ctx.runner.tasks[ctx.task.id].output = "Commit message looks good!"
      end
      
      ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
      ctx.runner.update_ui(ctx.win_id, nil, ctx.config)
      ctx.runner.update_signs(ctx.win_id)
    end, 500)
    
    return nil  -- We'll manage the state manually
  end,
}
```

## Best Practices

1. **Use Descriptive IDs and Labels**: Choose clear, descriptive IDs and labels for your tasks
2. **Add Icons**: Use Nerd Font icons to make your tasks visually distinguishable
3. **Handle Errors Gracefully**: Capture and report errors in a user-friendly way
4. **Provide Useful Output**: Store meaningful output in `task.output` for debugging
5. **Use Dependencies Wisely**: Create a logical flow with task dependencies
6. **Keep Tasks Focused**: Each task should do one thing well
7. **Consider Performance**: Use asynchronous operations for long-running tasks
8. **Add Timeouts**: Prevent tasks from running indefinitely

## Registering Custom Tasks

You can register custom tasks in several ways:

### 1. In Your Configuration File

```lua
-- ~/.smart-commit.lua or project-specific .smart-commit.lua
return {
  tasks = {
    ["my-custom-task"] = {
      id = "my-custom-task",
      label = "My Custom Task",
      command = "echo 'Hello from my task'",
    },
  },
}
```

### 2. Using the API

```lua
-- In your Neovim configuration
local smart_commit = require("smart-commit")

smart_commit.register_task("my-api-task", {
  label = "My API Task",
  command = "echo 'Registered via API'",
})
```

### 3. In a Plugin

```lua
-- In your plugin
local M = {}

function M.setup()
  local smart_commit = require("smart-commit")
  
  smart_commit.register_task("my-plugin-task", {
    label = "My Plugin Task",
    command = "echo 'From my plugin'",
  })
end

return M
```
