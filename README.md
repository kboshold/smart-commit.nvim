# Smart Commit for Neovim

A powerful, asynchronous Git commit workflow enhancement plugin for Neovim 0.11+. Smart Commit automatically runs configurable tasks when you open a Git commit buffer, providing real-time feedback and insights without blocking your editor.

![image](https://github.com/user-attachments/assets/c08cb433-1961-4b49-bdf9-f790d46d27c7)


## Features

- **Automatic Activation**: Runs when you open a Git commit buffer
- **Asynchronous Task Runner**: Execute tasks in parallel with dependency tracking
- **Real-time UI Feedback**: Non-intrusive sticky header shows task progress and status
- **Expandable Task Output**: Click or press Enter on tasks to view detailed command output
- **Hierarchical Task Display**: Callback tasks are visually indented under their parent tasks
- **Automatic Cleanup**: Force kills all running tasks when leaving the commit buffer
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
2. **User Global Config**: `~/.smart-commit.lua` in your home directory
3. **Parent Directory Configs**: `.smart-commit.lua` files in parent directories (loaded from root to current)
4. **Project-Specific Config**: `.smart-commit.lua` in your current project directory
5. **Runtime Setup**: The table passed to `setup({})`

**Example hierarchy:**
```
/home/user/.smart-commit.lua              # Global config
/home/user/workspace/.smart-commit.lua    # Workspace config  
/home/user/workspace/project/.smart-commit.lua  # Project config
```

When you're in `/home/user/workspace/project/subdir/`, all three config files will be loaded and merged, with later configs overriding earlier ones.

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
  predefined_tasks = {
    -- Define reusable task templates that don't run by default
    ["my-lint"] = {
      label = "My Custom Linter",
      icon = "󰉁",
      command = "eslint --fix .",
    },
    ["my-test"] = {
      label = "My Test Suite",
      icon = "󰙨",
      command = "npm test",
      timeout = 60000,
    },
  },
  tasks = {
    -- Task configurations (see below)
  },
})
```

### Predefined Tasks

Predefined tasks are reusable task templates that you can define once and use multiple times. They don't run by default - you need to explicitly enable them.

#### Defining Predefined Tasks

You can define predefined tasks in three places, and they are available across all configuration levels:

1. **Plugin setup** (lazy.nvim config):
```lua
{
  "kboshold/smart-commit.nvim",
  config = function()
    require("smart-commit").setup({
      predefined_tasks = {
        ["my-lint"] = {
          label = "My Linter",
          command = "eslint --fix .",
        },
      },
    })
  end,
}
```

2. **Global config** (`~/.smart-commit.lua`):
```lua
return {
  predefined_tasks = {
    ["global-lint-fix"] = {
      label = "Global Lint Fix",
      command = "eslint --fix .",
      timeout = 30000,
    },
    ["global-test"] = {
      label = "Global Test Suite", 
      command = "npm test",
    },
  },
}
```

3. **Project config** (`.smart-commit.lua`):
```lua
return {
  predefined_tasks = {
    ["project-build"] = {
      label = "Project Build",
      command = "npm run build",
    },
  },
  tasks = {
    -- Use global predefined tasks in project config
    ["global-test"] = true,
    ["global-lint-fix"] = true,
    
    -- Extend global predefined tasks
    ["custom-lint"] = {
      extend = "global-lint-fix",
      cwd = "./src",
    },
    
    -- Use project predefined tasks
    ["project-build"] = true,
  },
}
```

#### Cross-File Predefined Task Usage

Predefined tasks defined in parent configurations are automatically available in child configurations:

- **Setup predefined tasks** → Available in global and project configs
- **Global predefined tasks** → Available in project configs  
- **Project predefined tasks** → Available only in that project

This allows you to:
- Define common tasks once in your global config
- Use them across all your projects
- Extend them with project-specific customizations

#### Using Predefined Tasks

Once defined, you can use predefined tasks in your `tasks` configuration:

```lua
tasks = {
  -- Enable a predefined task with shorthand syntax
  ["my-lint"] = true,
  
  -- Extend a predefined task with custom properties
  ["custom-lint"] = {
    extend = "my-lint",
    label = "Custom Linter", -- Override the label
    timeout = 30000,         -- Add custom timeout
  },
  
  -- Use built-in predefined tasks
  ["copilot:message"] = true,
  ["copilot:analyze"] = true,
}
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
    command = {                -- Array of commands to execute sequentially
      "echo 'Step 1'",
      "npm install",
      "echo 'Step 2'",
    },
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
    on_success = "success-task", -- Task ID to run on success, or function to call
    on_fail = "failure-task",    -- Task ID to run on failure, or function to call
    -- OR use functions for more control:
    on_success = function(result)
      -- result.success, result.exit_code, result.output, result.stdout, result.stderr
      print("Task succeeded with exit code: " .. (result.exit_code or "N/A"))
    end,
    on_fail = function(result)
      -- result.success, result.exit_code, result.output, result.stdout, result.stderr
      print("Task failed with exit code: " .. (result.exit_code or "N/A"))
      print("Error output: " .. (result.stderr or result.output or ""))
    end,
    -- OR use arrays for multiple callbacks:
    on_success = {
      "deploy-task",           -- First run a deployment task
      function(result)         -- Then run a notification function
        vim.notify("Deployment successful!")
      end
    },
  },

  -- Disable a task by setting it to false
  ["some-task"] = false,

  -- Enable a predefined task with shorthand syntax
  ["my-predefined-task"] = true,

  -- Extend a predefined task
  ["custom-lint"] = {
    extend = "pnpm-lint",      -- ID of predefined task to extend
    label = "Custom Linter",   -- Override properties from base task
  },

  -- Use shorthand syntax for built-in predefined tasks
  ["copilot:message"] = true,  -- Enable the predefined copilot:message task
}
```

## Callback Examples

### Automatic Lint Fixing

Run a lint fix task when linting fails:

```lua
tasks = {
  ["pnpm-lint-fix"] = {
    extend = "pnpm",
    label = "PNPM Lint Fix",
    command = "eslint_d --fix .",
  },
  
  ["pnpm-lint"] = {
    extend = "pnpm",
    label = "PNPM Lint",
    command = "eslint_d --check .",
    on_fail = "pnpm-lint-fix", -- Run lint fix if linting fails
  },
}
```

**Status Window Display:**
```
Smart Commit Tasks
Status: ✓ All tasks completed (2.34s)
├ 󰉁 PNPM Lint ✗ Failed (1.12s)
  └ 󰔧 PNPM Lint Fix ✓ Success (1.22s)
```

Note how the callback task (PNPM Lint Fix) is visually indented under its parent task (PNPM Lint).

### Conditional Task Execution

Use functions for more complex callback logic:

```lua
tasks = {
  ["test"] = {
    command = "npm test",
    on_fail = function(result)
      if result.exit_code == 1 then
        -- Test failures - show detailed output
        print("Tests failed with output:")
        print(result.stderr or result.output)
      else
        -- Other errors - maybe run diagnostics
        vim.notify("Test command failed: " .. (result.error_message or "Unknown error"))
      end
    end,
    on_success = function(result)
      vim.notify("All tests passed! ✅")
    end,
  },
}
```

### Chained Task Execution

Create complex workflows with task chaining:

```lua
tasks = {
  ["build"] = {
    command = "npm run build",
    on_success = "deploy", -- Deploy only if build succeeds
  },
  
  ["deploy"] = {
    command = "npm run deploy",
    on_success = function(result)
      vim.notify("Deployment successful! 🚀")
    end,
    on_fail = function(result)
      vim.notify("Deployment failed: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
    end,
  },
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
  predefined_tasks = {
    -- Define project-specific predefined tasks
    ["project-lint-fix"] = {
      label = "Project Lint Fix",
      icon = "󰉁",
      extend = "pnpm",
      script = "lint:fix",
    },
  },
  tasks = {
    -- PNPM Lint task
    ["pnpm-lint"] = {
      label = "PNPM Lint",
      icon = "󰉁",
      extend = "pnpm",
      script = "lint",
      on_fail = "project-lint-fix", -- Use predefined task as callback
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

## Commands

Smart Commit provides several user commands for easy access:

- `:SmartCommitKill` - Kill all running tasks immediately
- `:SmartCommitRun` - Manually run tasks in the current buffer
- `:SmartCommitToggle` - Toggle auto-run on/off
- `:SmartCommitEnable` - Enable auto-run
- `:SmartCommitDisable` - Disable auto-run

### Interactive Controls

When the Smart Commit UI is active, you can interact with tasks:

- **`<Enter>`** - Toggle task output expansion on the current line
- **`<LeftMouse>`** - Click on any task line to toggle its output
- **Visual Indicators**: 
  - `▶` - Task has output available (collapsed)
  - `▼` - Task output is currently expanded
  - No indicator - Task has no output to display

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

-- Kill all running tasks (useful for cleanup)
smart_commit.kill_all_tasks()

-- Register a custom task programmatically
smart_commit.register_task("my-task", {
  label = "My Custom Task",
  command = "echo 'Hello from my task'",
})
```

## Environment Variables

- `SMART_COMMIT_ENABLED=0`: Disable Smart Commit for a specific commit

## Task Management

### Automatic Cleanup

Smart Commit automatically manages running tasks to prevent orphaned processes:

- **Buffer Leave**: When you leave the commit buffer (switch to another buffer), all running tasks are immediately force-killed
- **Buffer Delete**: When the commit buffer is deleted, all running tasks are force-killed
- **Graceful Termination**: Tasks are first sent a SIGTERM signal, followed by SIGKILL after 1 second if still running
- **State Updates**: Killed tasks are marked as aborted with a note indicating they were terminated by the user

This ensures that no background processes continue running after you've finished with your commit, preventing resource leaks and unexpected behavior.

### Manual Task Control

You can also manually control tasks using the API:

```lua
-- Kill all running tasks immediately
require("smart-commit").kill_all_tasks()
```

## Expandable Task Output

Smart Commit provides an interactive UI that allows you to view detailed output from your tasks without cluttering the interface.

### **Visual Indicators**

- **▶** - Task has output available (collapsed)
- **▼** - Task output is currently expanded
- **No indicator** - Task has no output to display

### **Interaction Methods**

- **Enter Key**: Press `<Enter>` on any task line to toggle its output
- **Mouse Click**: Click on any task line to toggle its output

### **Output Display**

When expanded, task output is displayed with:
- **Proper Indentation**: Output is indented for visual clarity
- **Multi-line Support**: Each line of output is displayed separately
- **Command Separators**: For array commands, each command's output is clearly separated
- **Automatic Formatting**: Long lines are preserved as-is for accurate debugging

### **Example**

```
Smart Commit Tasks
Status: ✓ All tasks completed (2.34s)
├ ▼ 󰉁 PNPM Lint ✓ Success (1.12s)
    Command executed successfully
    Found 0 errors, 2 warnings
    All files processed
├ ▶ 󰙨 PNPM Test ✓ Success (0.89s)
└   No output indicator for tasks without output
```

### **Benefits**

- **Clean Interface**: Only show output when needed
- **Easy Debugging**: Quickly access command output for failed tasks
- **Efficient Workflow**: Toggle output without leaving the commit buffer
- **Context Preservation**: Output stays visible until manually collapsed

## Task States

Tasks can be in one of the following states:

- **Pending**: Task is waiting to be run
- **Waiting**: Task is waiting for dependencies to complete
- **Running**: Task is currently executing
- **Success**: Task completed successfully
- **Failed**: Task failed to complete
- **Aborted**: Task was killed/aborted by user
- **Skipped**: Task was skipped due to conditions

## Command Arrays

Smart Commit supports executing multiple commands sequentially within a single task by using an array of commands:

```lua
tasks = {
  ["build-and-test"] = {
    id = "build-and-test",
    label = "Build and Test",
    command = {
      "echo 'Starting build process...'",
      "npm run build",
      "echo 'Build complete, running tests...'",
      "npm test",
      "echo 'All steps completed successfully!'",
    },
  },
}
```

### Array Command Behavior

- **Sequential Execution**: Commands are executed one after another in the order specified
- **Failure Handling**: If any command fails (non-zero exit code), the entire sequence stops and the task is marked as failed
- **Output Aggregation**: Output from all commands is combined and displayed together
- **Command Separators**: Each command's output is automatically separated for clarity

### Dynamic Command Arrays

You can also use functions to generate command arrays dynamically:

```lua
tasks = {
  ["dynamic-sequence"] = {
    id = "dynamic-sequence",
    label = "Dynamic Sequence",
    command = function()
      local commands = {"echo 'Starting...'"}
      
      -- Add conditional commands based on environment
      if vim.fn.executable("pnpm") == 1 then
        table.insert(commands, "pnpm install")
        table.insert(commands, "pnpm build")
      else
        table.insert(commands, "npm install")
        table.insert(commands, "npm run build")
      end
      
      table.insert(commands, "echo 'Process complete!'")
      return commands
    end,
  },
}
```

### Use Cases

Command arrays are particularly useful for:

- **Multi-step build processes**: Compile, bundle, and optimize in sequence
- **Setup and teardown**: Prepare environment, run task, clean up
- **Conditional workflows**: Execute different commands based on conditions
- **Progress reporting**: Add echo commands between steps for better visibility

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

### Debug Mode

Enable debug mode to see which config files are being loaded and which predefined tasks are registered:

```bash
SMART_COMMIT_DEBUG=1 git commit
```

**Note**: The debug flag is cached when the plugin loads to avoid issues with Neovim's fast event contexts. If you need to change the debug setting during a session, restart Neovim or reload the plugin.

This will show output like:
```
Smart Commit: Loading config files:
  - /home/user/.smart-commit.lua
    → 2 predefined tasks
    → 1 tasks
  - /home/user/workspace/project/.smart-commit.lua
    → 1 predefined tasks
    → 3 tasks
Smart Commit: Registered predefined task 'global-lint' from /home/user/.smart-commit.lua
Smart Commit: Using predefined task 'pnpm:eslint-fix' as callback
Smart Commit: Final config has 4 tasks
```

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
