local registry = require("fzf.registry")

local nvim_fzf_directory = vim.g.nvim_fzf_directory
local shell_script_path = string.format("%s/action_helper.sh", nvim_fzf_directory)

local function escape(str)
  return vim.fn.shellescape(str)
end

local function raw_action(fn)
  local id = registry.register_func(fn)
  local action_string = string.format("%s %s %s {+}",
    escape(shell_script_path), escape(nvim_fzf_directory), id)
  return action_string, id
end

local function action(fn)
  local action_string, id = raw_action(fn)
  return escape(action_string), id
end

return {
  action = action,
  raw_action = raw_action
}
