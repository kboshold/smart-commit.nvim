-- Smart Commit PNPM Task Factory
-- Author: kboshold

local M = {}

-- Flag to track if pnpm install has been run in this session
local _pnpm_install_run = false

-- Cache for available scripts
local _available_scripts = nil

-- Get available pnpm scripts
local function get_available_scripts()
  if _available_scripts then
    return _available_scripts
  end

  -- Try to read package.json directly instead of using pnpm run --list
  local package_json_path = vim.fn.getcwd() .. "/package.json"
  if vim.fn.filereadable(package_json_path) == 0 then
    _available_scripts = {}
    return {}
  end

  local package_json_content = vim.fn.readfile(package_json_path)
  local package_json = vim.fn.json_decode(table.concat(package_json_content, "\n"))

  if not package_json or not package_json.scripts then
    _available_scripts = {}
    return {}
  end

  -- Extract scripts from package.json
  local scripts = {}
  for script_name, _ in pairs(package_json.scripts) do
    scripts[script_name] = true
  end

  _available_scripts = scripts
  return scripts
end

-- Run pnpm install if it hasn't been run yet in this session
local function ensure_dependencies()
  if _pnpm_install_run then
    return true
  end

  -- Always run pnpm install

  -- Check if pnpm is installed
  local pnpm_exists = vim.fn.executable("pnpm") == 1
  if not pnpm_exists then
    vim.notify("PNPM is not installed or not in PATH", vim.log.levels.ERROR)
    _pnpm_install_run = true
    return false
  end

  -- Mark as run immediately to prevent multiple installs
  _pnpm_install_run = true

  -- Run pnpm install asynchronously
  vim.system({ "pnpm", "install" }, {
    stdout = function(_, data) end,
    stderr = function(_, data)
      if data then
        vim.schedule(function()
          vim.notify("pnpm install error: " .. data, vim.log.levels.WARN)
        end)
      end
    end,
  }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        -- Refresh available scripts after install
        _available_scripts = nil
      else
        vim.notify("pnpm install failed with code: " .. obj.code, vim.log.levels.ERROR)
      end
    end)
  end)

  -- Return true immediately, don't wait for install to complete
  return true
end

-- Base PNPM task that can be extended
---@type SmartCommitTask
M.base_task = {
  id = "pnpm",
  label = "PNPM Task",
  script = nil, -- To be set by extending tasks
  command = function(self)
    -- Ensure dependencies are installed
    if not ensure_dependencies() then
      vim.notify("Failed to ensure dependencies for " .. self.id, vim.log.levels.ERROR)
      return "echo 'Failed to ensure dependencies'"
    end

    -- Check if a script is specified
    if not self.script then
      vim.notify("No script specified for PNPM task", vim.log.levels.ERROR)
      return "echo 'No script specified'"
    end

    -- Check if the script exists
    local scripts = get_available_scripts()

    if not scripts[self.script] then
      vim.notify("Script '" .. self.script .. "' not found in package.json", vim.log.levels.WARN)
      return "echo 'Script " .. self.script .. " not found in package.json'"
    end

    -- Run the script
    local cmd = "pnpm " .. self.script
    return cmd
  end,
  when = function()
    -- Only run if package.json exists
    local has_package = vim.fn.filereadable("package.json") == 1
    return has_package
  end,
}

-- Reset the install check flag (useful for testing)
function M.reset_install_check()
  _pnpm_install_run = false
  _available_scripts = nil
end

return M
