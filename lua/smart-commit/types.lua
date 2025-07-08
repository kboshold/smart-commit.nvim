-- Smart Commit Type Definitions
-- Author: kboshold

local M = {}

---@class SmartCommitStatusWindowConfig
---@field enabled? boolean # Show status window. Default: true.
---@field position? "bottom" | "top" # Position of the header split. Default: 'bottom'.
---@field refresh_rate? number # UI refresh rate in milliseconds. Default: 100.

---@class SmartCommitDefaults
---@field cwd? string # Default working directory for tasks. Default: vim.fn.getcwd().
---@field timeout? number # Default task timeout in ms. Default: 30000.
---@field concurrency? number # Max number of concurrent tasks. Default: 4.
---@field auto_run? boolean # Automatically run on commit message buffer open. Default: true.
---@field sign_column? boolean # Show signs in the sign column. Default: true.
---@field hide_skipped? boolean # Hide tasks that were skipped. Default: false.
---@field status_window? SmartCommitStatusWindowConfig

---@alias TaskFn fun():(boolean | {ok: boolean, message: string})
---@alias ConditionFn fun():boolean

---@class TaskResult
---@field success boolean # Whether the task succeeded
---@field exit_code? number # Exit code for shell commands
---@field output? string # Combined stdout/stderr output
---@field stderr? string # Standard error output
---@field stdout? string # Standard output
---@field error_message? string # Error message if any

---@alias TaskCallbackFn fun(result: TaskResult): nil
---@alias TaskCallback string | TaskCallbackFn | (string | TaskCallbackFn)[] # Either a task ID, a function, or an array of tasks/functions

---@class TaskContext
---@field win_id number # The window ID of the commit buffer
---@field buf_id number # The buffer ID of the commit buffer
---@field runner table # Reference to the runner module
---@field task SmartCommitTask # The task being executed
---@field config SmartCommitConfig # The full configuration

---@alias TaskHandlerFn fun(ctx: TaskContext):(boolean | string | nil)

---@class SmartCommitTask
---@field id string # Required, unique identifier for the task.
---@field label string # Human-readable name for the UI.
---@field extend? string # ID of a predefined task to extend. Overrides properties from the base task.
---@field icon? string # Icon to display (Nerd Font recommended).
---@field command? string | fun():string # Shell command to execute.
---@field fn? TaskFn # Lua function to execute. (Alternative to 'command').
---@field handler? TaskHandlerFn # Advanced handler function with access to context. Takes precedence over command and fn.
---@field cwd? string # Working directory for this specific task.
---@field when? ConditionFn # Function to determine if the task should run. Must return true for the task to be scheduled.
---@field timeout? number # Timeout in milliseconds for this task.
---@field depends_on? string[] # List of task 'id's that must complete successfully first.
---@field on_success? TaskCallback # Callback when task succeeds - either task ID to run or function to call.
---@field on_fail? TaskCallback # Callback when task fails - either task ID to run or function to call.
---@field env? table<string, string> # Environment variables for the task's command.

---@class SmartCommitConfig
---@field defaults? SmartCommitDefaults
---@field predefined_tasks? table<string, SmartCommitTask> # User-defined predefined tasks that don't run by default
---@field tasks? table<string, SmartCommitTask | false | true> # A map of task configurations. Setting a task to `false` disables it, `true` enables a predefined task.

--- A chunk of text with an associated highlight group.
---@class StickyHeaderChunk
---@field text string The text to display.
---@field highlight_group string The highlight group to apply to the text.

--- A single line in the header, composed of multiple text chunks.
---@alias StickyHeaderLine StickyHeaderChunk[]

--- The entire content for the sticky header.
---@alias StickyHeaderContent StickyHeaderLine[]

--- Internal state of a header instance.
---@class StickyHeaderState
---@field header_win_id number The window ID of the header split.
---@field header_buf_id number The buffer ID of the header split.
---@field target_win_id number The window ID of the buffer the header is attached to.
---@field is_visible boolean

return M
