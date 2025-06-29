-- Smart Commit Copilot Tasks
-- Author: kboshold

local M = {}

-- Get the current Git branch name
---@return string|nil The current branch name or nil if not in a Git repository
local function get_current_branch()
  local result = vim.fn.system("git rev-parse --abbrev-ref HEAD")
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get current Git branch", vim.log.levels.WARN)
    return nil
  end
  return vim.trim(result)
end

-- Get the staged changes as a diff
---@return string The staged changes as a diff
local function get_staged_changes()
  local result = vim.fn.system("git diff --staged")
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get staged changes", vim.log.levels.WARN)
    return ""
  end
  return result
end

-- Parse branch name to determine commit scope
---@param branch_name string The branch name to parse
---@return string|nil scope The commit scope or nil if not found
local function get_commit_scope()
  local branch = get_current_branch()
  if not branch then
    return nil
  end

  local scope = ""
  if branch ~= "main" and branch ~= "develop" then
    scope = branch:match("^[^/]+/(.+)")

    if scope and scope:match("%-") then
      local ticket_num = scope:match("^(%d+)%-?")
      if ticket_num then
        scope = "#" .. ticket_num
      else
        local jira_ticket = scope:match("^([A-Z]+%-[0-9]+)%-?")
        if jira_ticket then
          scope = jira_ticket
        else
          scope = "#" .. scope:match("^([^-]+)")
        end
      end
    end
  end

  return scope
end

-- Task to analyze staged code changes
---@type SmartCommitTask
M.analyze_staged = {
  id = "copilot:analyze",
  label = "Analyze Staged Changes",
  icon = "󰟌",
  handler = function(ctx)
    -- Check if CopilotChat is available
    if not pcall(require, "CopilotChat") then
      vim.notify("CopilotChat.nvim is not available", vim.log.levels.ERROR)
      return false
    end

    local CopilotChat = require("CopilotChat")

    -- Get staged changes
    local staged_changes = get_staged_changes()
    if staged_changes == "" then
      vim.notify("No staged changes to analyze", vim.log.levels.WARN)
      ctx.runner.tasks[ctx.task.id].output = "No staged changes to analyze"
      ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.SKIPPED
      ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
      ctx.runner.update_ui(ctx.win_id)
      ctx.runner.update_signs(ctx.win_id)
      return nil
    end

    -- Construct the prompt for Copilot
    local prompt = [[
Analyze the staged code changes and provide a concise summary of:

1. Potential issues or bugs (debug statements, commented code, obvious errors)
2. Security concerns (hardcoded credentials, insecure practices)
3. Performance considerations
4. Code quality observations (duplicated code, complex logic)

Format your response as a brief, actionable summary with bullet points for each category.
Keep your response under 300 words and focus only on significant findings.
If there are no issues in a category, simply state "No issues found".
]]

    -- Use headless mode with callback
    CopilotChat.ask(prompt, {
      headless = true,
      context = {
        "git:staged",
      },
      callback = function(response)
        if not response or response == "" then
          vim.notify("Failed to analyze staged changes", vim.log.levels.ERROR)

          -- Update task status to failed
          vim.schedule(function()
            ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
            ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
            ctx.runner.update_ui(ctx.win_id)
            ctx.runner.update_signs(ctx.win_id)
          end)
          return
        end
        
        -- Check for quota exceeded message
        if response:match("[Qq]uota exceeded") or response:match("[Qq]uota extended") then
          vim.notify("Copilot quota exceeded", vim.log.levels.ERROR)
          
          -- Update task status to failed
          vim.schedule(function()
            ctx.runner.tasks[ctx.task.id].output = "Copilot quota exceeded"
            ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
            ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
            ctx.runner.update_ui(ctx.win_id)
            ctx.runner.update_signs(ctx.win_id)
          end)
          return
        end

        -- Store the analysis in the task output
        ctx.runner.tasks[ctx.task.id].output = response

        -- Create a floating window to display the analysis
        vim.schedule(function()
          -- Update task status to success
          ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.SUCCESS
          ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
          ctx.runner.update_ui(ctx.win_id)
          ctx.runner.update_signs(ctx.win_id)

          -- Use the UI module to show the analysis in a floating window on the right
          local ui = require("smart-commit.ui")
          ui.show_analysis(ctx.win_id, "Code Analysis Results", response)
        end)
      end,
    })

    -- Return nil to indicate that the handler is managing the task state asynchronously
    return nil
  end,
}

-- Task to generate a commit message
---@type SmartCommitTask
M.generate_commit_message = {
  id = "copilot:message",
  label = "Generate Commit Message",
  icon = "",
  handler = function(ctx)
    -- Get commit scope from branch name
    local scope = get_commit_scope()

    -- Check if CopilotChat is available
    if not pcall(require, "CopilotChat") then
      vim.notify("CopilotChat.nvim is not available", vim.log.levels.ERROR)
      return false
    end

    local CopilotChat = require("CopilotChat")

    -- Construct the prompt for Copilot based on the old prompt.lua
    local prompt = [[
Write a conventional commits style (https://www.conventionalcommits.org/en/v1.0.0/) commit message for my changes. Please create only the code block without further explanations.

**Requirements:**

- Title: under 50 characters and talk imperative. Follow this rule: If applied, this commit will <commit message>
- Body: wrap at 72 characters
- Include essential information only
- Format as `gitcommit` code block
- Prepend a header with the lines to replace. It should only replace the lines in font of the first comment.
- Use `]] .. (scope or "") .. [[` as the scope. If the scope is empty then skip it. If it includes a `#`, also add it in the scope.

Use the following example as reference. Do only use it to understand the format but dont use the information of it.

```gitcommit
feat(scope): add login functionality

Implement user authentication flow with proper validation
and error handling. Connects to the auth API endpoint.
```

Only create the commit message. Do not explain anything!
]]

    -- Use headless mode with callback
    CopilotChat.ask(prompt, {
      headless = true,
      context = {
        "git:staged",
        "file:`.git/COMMIT_EDITMSG`",
      },
      callback = function(response)
        if not response or response == "" then
          vim.notify("Failed to generate commit message", vim.log.levels.ERROR)

          -- Update task status to failed
          vim.schedule(function()
            ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
            ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
            ctx.runner.update_ui(ctx.win_id)
            ctx.runner.update_signs(ctx.win_id)
          end)
          return
        end
        
        -- Check for quota exceeded message
        if response:match("[Qq]uota exceeded") or response:match("[Qq]uota extended") then
          vim.notify("Copilot quota exceeded", vim.log.levels.ERROR)
          
          -- Update task status to failed
          vim.schedule(function()
            ctx.runner.tasks[ctx.task.id].output = "Copilot quota exceeded"
            ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
            ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
            ctx.runner.update_ui(ctx.win_id, nil, ctx.config)
            ctx.runner.update_signs(ctx.win_id)
          end)
          return
        end

        -- Extract the gitcommit code block if present
        local commit_message = response:match("```gitcommit\n(.-)\n```")
        if not commit_message then
          -- If no code block found, just clean up markdown formatting
          commit_message = response:gsub("```[%w]*\n", ""):gsub("```", "")
        end

        -- Insert the commit message into the buffer
        vim.schedule(function()
          -- Make sure buffer still exists
          if not vim.api.nvim_buf_is_valid(ctx.buf_id) then
            vim.notify("Commit buffer no longer valid", vim.log.levels.ERROR)

            -- Update task status to failed
            ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.FAILED
            ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
            ctx.runner.update_ui(ctx.win_id)
            ctx.runner.update_signs(ctx.win_id)
            return
          end

          -- Get existing content
          local existing_lines = vim.api.nvim_buf_get_lines(ctx.buf_id, 0, -1, false)

          -- Prepare the commit message lines, preserving all line breaks
          local message_lines = {}

          -- Split by line breaks, preserving empty lines
          for line in (commit_message .. "\n"):gmatch("([^\n]*)[\n]") do
            table.insert(message_lines, line)
          end

          -- Ensure there's a blank line after the first line (between subject and body)
          if #message_lines >= 2 then
            if message_lines[2] ~= "" then
              table.insert(message_lines, 2, "")
            end
          end

          -- Add an empty line between the generated message and existing content
          -- if there isn't already one at the end of the message
          if #message_lines > 0 and message_lines[#message_lines] ~= "" then
            table.insert(message_lines, "")
          end

          -- Prepend the generated message to the existing content
          for i, line in ipairs(existing_lines) do
            table.insert(message_lines, line)
          end

          -- Update the buffer with the combined content
          vim.api.nvim_buf_set_lines(ctx.buf_id, 0, -1, false, message_lines)

          -- Update task status to success
          ctx.runner.tasks[ctx.task.id].state = ctx.runner.TASK_STATE.SUCCESS
          ctx.runner.tasks[ctx.task.id].end_time = vim.loop.now()
          ctx.runner.update_ui(ctx.win_id, nil, ctx.config)
          ctx.runner.update_signs(ctx.win_id)
        end)
      end,
    })

    -- Return nil to indicate that the handler is managing the task state asynchronously
    return nil
  end,
}

return M
