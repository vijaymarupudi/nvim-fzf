local registry = require("fzf.registry")

local M = {}

local function escape(str)
  return vim.fn.shellescape(str)
end

function M.raw_action(fn, filespec)
  local nvim_fzf_directory = vim.g.nvim_fzf_directory
  local id = registry.register_func(fn)
  local action_string = string.format("nvim --headless --clean --cmd %s %s %s %s",
    vim.fn.shellescape("luafile " .. nvim_fzf_directory .. "/action_helper.lua"),
    vim.fn.shellescape(nvim_fzf_directory),
    id, filespec or "{+}")
  return action_string, id
end

function M.action(fn, filespec)
  local action_string, id = M.raw_action(fn, filespec)
  return escape(action_string), id
end

return M
