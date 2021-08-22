local registry = require("fzf.registry")
local uv = vim.loop

local M = {}

local escape = vim.fn.shellescape

function M.raw_async_action(fn)

  local nvim_fzf_directory = vim.g.nvim_fzf_directory

  local receiving_function = function(pipe_path, ...)
    local pipe = uv.new_pipe(false)
    local args = {...}
    uv.pipe_connect(pipe, pipe_path, function(err)
      vim.schedule(function ()
        fn(pipe, unpack(args))
      end)
    end)
  end

  local id = registry.register_func(receiving_function)

  -- this is for windows WSL and AppImage users, their nvim path isn't just
  -- 'nvim', it can be something else
  local nvim_command = vim.v.argv[1]

  local action_string = string.format("%s --headless --clean --cmd %s %s %s {+}",
    vim.fn.shellescape(nvim_command),
    vim.fn.shellescape("luafile " .. nvim_fzf_directory .. "/action_helper.lua"),
    vim.fn.shellescape(nvim_fzf_directory),
    id)
  return action_string, id
end

function M.async_action(fn)
  local action_string, id = M.raw_async_action(fn)
  return escape(action_string), id
end

function M.raw_action(fn)

  local receiving_function = function(pipe, ...)
    local ret = fn(...)

    local on_complete = function()
      uv.close(pipe)
    end

    if type(ret) == "string" then
      uv.write(pipe, ret, function (err)
        assert(not err)
        on_complete()
      end)
    elseif type(ret) == nil then
      on_complete()
    elseif type(ret) == "table" then
      local new_ret = {}
      for i, v in ipairs(ret) do
        table.insert(new_ret, tostring(v) .. "\n")
      end
      ret = new_ret

      local all_err = nil
      local n_completed = 0
      local cb = function(err)
        if err then
          all_err = true
          on_complete()
          return
        end

        if all_err then
          return
        end
        n_completed = n_completed + 1
        if n_completed == #ret then
          on_complete()
        end
      end
      for i, v in ipairs(ret) do
        uv.write(pipe, v, cb)        
      end
    else
      uv.write(pipe, tostring(ret) .. "\n", function (err)
        assert(not err)
        on_complete()
      end)
    end
  end

  return M.raw_async_action(receiving_function)
end

function M.action(fn)
  local action_string, id = M.raw_action(fn)
  return escape(action_string), id
end

return M
