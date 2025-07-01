# Smart Commit for Neovim

A powerful, asynchronous Git commit workflow enhancement plugin for Neovim 0.11+. Smart Commit automatically runs configurable tasks when you open a Git commit buffer, providing real-time feedback and insights without blocking your editor.

![image](https://github.com/user-attachments/assets/c08cb433-1961-4b49-bdf9-f790d46d27c7)


## Features

- **Automatic Activation**: Runs when you open a Git commit buffer
- **Asynchronous Task Runner**: Execute tasks in parallel with dependency tracking
- **Real-time UI Feedback**: Non-intrusive sticky header shows task progress and status
- **Hierarchical Configuration**: Merge settings from plugin defaults, user config, and project-specific files
- **Extensible Task System**: Create custom tasks or extend predefined ones
- **Copilot Integration**: Generate commit messages and analyze staged changes with GitHub Copilot
- **PNPM Support**: Built-in tasks for PNPM-based projects

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "kboshold/smart-commit.nvim",
  lazy = false,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "CopilotC-Nvim/CopilotChat.nvim", -- Optional: Required for commit message generation
  },
  config = function()
    require("smart-commit").setup({
      defaults = {
        auto_run = true,
        sign_column = true,
        hide_skipped = true,
      },
    })
  end,
  keys = {
    {
      "<leader>sc",
      function()
        require("smart-commit").toggle()
      end,
      desc = "Toggle Smart Commit",
    },
  },
}
```

## Configuration

Smart Commit uses a hierarchical configuration system that merges settings from multiple sources:

1. **Plugin Defaults**: Base configuration defined within the plugin
2. **User Global Config**: `~/.smart-commit.lua` in your Neovim config directory
3. **Project-Specific Config**: `.smart-commit.lua` in your project directory
4. **Runtime Setup**: The table passed to `setup({})`

### Configuration Options

```lua
require("smart-commit").setup({
  defaults = {
    auto_run = true,           -- Automatically run on commit buffer open
    sign_column = true,        -- Show signs in the sign column
    hide_skipped = false,      -- Whether to hide skipped tasks in the UI
    status_window = {
      enabled = true,          -- Show status window
      position = "bottom",     -- Position of the header split
      refresh_rate = 100,      -- UI refresh rate in milliseconds
    },
  },
  tasks = {
    -- Task configurations (see below)
  },
})
```

### Task Configuration

Tasks are defined as a map of task IDs to task configurations:

```lua
tasks = {
  ["task-id"] = {
    id = "task-id",            -- Required, unique identifier
    label = "Human Label",     -- Human-readable name for the UI
    icon = "󰉁",               -- Icon to display (Nerd Font recommended)
    command = "echo 'hello'",  -- Shell command to execute
    -- OR
    fn = function()            -- Lua function to execute
      -- Do something
      return true              -- Return true for success, false for failure
    end,
    -- OR
    handler = function(ctx)    -- Advanced handler with context
      -- Access ctx.win_id, ctx.buf_id, ctx.runner, ctx.task, ctx.config
      return true              -- Return true/false for success/failure
                               -- Return string to run as shell command
                               -- Return nil to manage task state manually
    end,
    when = function()          -- Function to determine if task should run
      return true              -- Return true to run, false to skip
    end,
    depends_on = { "other-task" }, -- List of task IDs that must complete first
    timeout = 30000,           -- Timeout in milliseconds
    cwd = "/path/to/dir",      -- Working directory for this task
    env = {                    -- Environment variables
      NODE_ENV = "development"
    },
  },

  -- Disable a task by setting it to false
  ["some-task"] = false,

  -- Extend a predefined task
  ["custom-lint"] = {
    extend = "pnpm-lint",      -- ID of predefined task to extend
    label = "Custom Linter",   -- Override properties from base task
  },

  -- Use shorthand syntax for predefined tasks
  ["copilot:message"] = true,  -- Enable the predefined copilot:message task
}
```

## Project-Specific Configuration

Create a `.smart-commit.lua` file in your project root:

```lua
-- .smart-commit.lua
return {
  defaults = {
    hide_skipped = true,
  },
  tasks = {
    -- PNPM Lint task
    ["pnpm-lint"] = {
      label = "PNPM Lint",
      icon = "󰉁",
      extend = "pnpm",
      script = "lint",
    },

    -- PNPM Prisma Generate task
    ["pnpm-prisma-generate"] = {
      label = "PNPM Prisma Generate",
      icon = "󰆼",
      extend = "pnpm",
      script = "prisma generate",
    },

    -- PNPM Typecheck task (depends on prisma generate)
    ["pnpm-typecheck"] = {
      label = "PNPM Typecheck",
      icon = "󰯱",
      extend = "pnpm",
      script = "typecheck",
      depends_on = { "pnpm-prisma-generate" },
    },

    -- Copilot message task (using shorthand syntax)
    ["copilot:message"] = true,

    -- Code analysis task (using shorthand syntax)
    ["copilot:analyze"] = true,
  },
}
```

## Predefined Tasks

Smart Commit comes with several predefined tasks that you can use or extend:

### PNPM Tasks

- **pnpm**: Base task for PNPM projects (meant to be extended)
  - Automatically checks for and installs node_modules if missing
  - Verifies script exists in package.json before running

Example:

```lua
["pnpm-lint"] = {
  extend = "pnpm",
  script = "lint",  -- Will run "pnpm lint"
}
```

### Copilot Tasks

- **copilot:message**: Generates a commit message using GitHub Copilot

  - Analyzes staged changes
  - Parses branch name for commit type and scope
  - Follows Conventional Commits format

- **copilot:analyze**: Analyzes staged changes for potential issues
  - Identifies bugs, security concerns, and code quality issues
  - Displays results in a side panel

## API

Smart Commit provides a public API for programmatic usage:

```lua
local smart_commit = require("smart-commit")

-- Enable/disable the plugin
smart_commit.enable()
smart_commit.disable()
smart_commit.toggle()

-- Run tasks manually
smart_commit.run_tasks()

-- Register a custom task programmatically
smart_commit.register_task("my-task", {
  label = "My Custom Task",
  command = "echo 'Hello from my task'",
})
```

## Environment Variables

- `SMART_COMMIT_ENABLED=0`: Disable Smart Commit for a specific commit

## Task States

Tasks can be in one of the following states:

- **Pending**: Task is waiting to be run
- **Waiting**: Task is waiting for dependencies to complete
- **Running**: Task is currently executing
- **Success**: Task completed successfully
- **Failed**: Task failed to complete
- **Skipped**: Task was skipped due to conditions

## Creating Custom Tasks

You can create custom tasks in several ways:

### 1. Simple Command Task

```lua
["my-command"] = {
  id = "my-command",
  label = "My Command",
  command = "echo 'Hello World'",
}
```

### 2. Dynamic Command Task

```lua
["dynamic-command"] = {
  id = "dynamic-command",
  label = "Dynamic Command",
  command = function(task)
    return "echo 'Running " .. task.id .. "'"
  end,
}
```

### 3. Lua Function Task

```lua
["lua-function"] = {
  id = "lua-function",
  label = "Lua Function",
  fn = function()
    -- Do something
    return true -- Return true for success, false for failure
  end,
}
```

### 4. Advanced Handler Task

```lua
["advanced-handler"] = {
  id = "advanced-handler",
  label = "Advanced Handler",
  handler = function(ctx)
    -- Access context
    local win_id = ctx.win_id
    local buf_id = ctx.buf_id
    local runner = ctx.runner

    -- Do something asynchronous
    vim.schedule(function()
      -- Update task state manually
      runner.tasks[ctx.task.id].state = runner.TASK_STATE.SUCCESS
      runner.tasks[ctx.task.id].end_time = vim.loop.now()
      runner.update_ui(win_id)
      runner.update_signs(win_id)
    end)

    -- Return nil to indicate manual state management
    return nil
  end,
}
```

## Troubleshooting

### Task Not Running

- Check if the task is disabled in your configuration
- Verify that any dependencies are completing successfully
- Check if the `when` condition is returning `false`

### Copilot Tasks Not Working

- Ensure CopilotChat.nvim is installed and configured
- Check if you have exceeded your Copilot quota
- Verify that you have staged changes for analysis

### Performance Issues

- Reduce the number of concurrent tasks
- Increase the refresh rate of the status window
- Disable tasks that are not essential

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgements

- Inspired by pre-commit hooks and CI/CD pipelines
- Built with Neovim 0.11's modern APIs
- Special thanks to the Neovim community
