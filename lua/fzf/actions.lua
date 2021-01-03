local registry = require("fzf.registry")

local nvim_fzf_directory = vim.g.nvim_fzf_directory
local shell_script_path = string.format("%s/action_helper.sh", nvim_fzf_directory)

local function escape(str)
  return string.format("'%s'", vim.fn.escape(str, "'"))
end

local function function_to_action(fn)
  local id = registry.register_func(fn)
  return string.format("%s %s %s {+}",
    escape(shell_script_path), escape(nvim_fzf_directory), id), id
end

return { function_to_action = function_to_action }
