local registry = require("fzf.registry")
local uv = vim.loop

local M = {}

local escape = vim.fn.shellescape


local function lua_escape(str)
   local items = {}
   local start_index = 1
   local location = string.find(str, "]]", start_index, true)
   while location do
      local good_part = string.sub(str, start_index, location - 1)
      table.insert(items, "[[" .. good_part .. "]]")
      table.insert(items, "\"" .. "]]" .. "\"")
      start_index = location + 2
      location = string.find(str, "]]", start_index, true)
   end
   table.insert(items, "[[" .. string.sub(str, start_index) .. "]]")
   return table.concat(items, "..")
end


-- creates a new address to listen to messages from actions. This is important,
-- if the user is using a custom fixed $NVIM_LISTEN_ADDRESS. Different neovim
-- instances will then use the same path as the address and it causes a mess,
-- i.e. actions stop working on the old instance. So we create our own (random
-- path) RPC server for this instance if it hasn't been started already.
local action_server_address = nil

function M.raw_async_action(fn, fzf_field_expression)

  if not fzf_field_expression then
    fzf_field_expression = "{+}"
  end

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

  if not action_server_address then
    action_server_address = vim.fn.serverstart()
  end

  local id = registry.register_func(receiving_function)


  -- this is for windows WSL and AppImage users, their nvim path isn't just
  -- 'nvim', it can be something else
  local nvim_command = vim.v.argv[1]

  local call_arg_table_string = ("{ action_server=%s, function_id=%d }"):format(
     lua_escape(action_server_address), id)

  local action_helper_vim_cmd = vim.fn.shellescape(("lua loadfile(%s)().rpc_nvim_exec_lua(%s)")
     :format(lua_escape(nvim_fzf_directory .. "/action_helper.lua"),
             call_arg_table_string))

  local action_string = string.format("%s -n --headless --clean --cmd %s %s",
    vim.fn.shellescape(nvim_command),
    action_helper_vim_cmd,
    fzf_field_expression)

  return action_string, id
end

function M.async_action(fn, fzf_field_expression)
  local action_string, id = M.raw_async_action(fn, fzf_field_expression)
  return escape(action_string), id
end

function M.raw_action(fn, fzf_field_expression)

  local receiving_function = function(pipe, ...)
    local ret = fn(...)

    local on_complete = function()
      uv.close(pipe)
    end

    if type(ret) == "string" then
      uv.write(pipe, ret, function (err)
        -- We are NOT asserting, in case fzf closes the pipe before we can send
        -- the preview.
        -- assert(not err)
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
        -- We are NOT asserting, in case fzf closes the pipe before we can send
        -- the preview.
        -- assert(not err) 
        on_complete()
      end)
    end
  end

  return M.raw_async_action(receiving_function, fzf_field_expression)
end

function M.action(fn, fzf_field_expression)
  local action_string, id = M.raw_action(fn, fzf_field_expression)
  return escape(action_string), id
end

return M
