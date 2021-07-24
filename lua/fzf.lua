local uv = vim.loop
local float = require('fzf.floating_window')

local FZF = {}

local function coroutine_callback(func)
  local co = coroutine.running()
  local callback = function(...)
    coroutine.resume(co, ...)
  end
  func(callback)
  return coroutine.yield()
end

local function coroutinify(func)
  return function (...)
    local args = {...}
    return coroutine_callback(function (cb)
      table.insert(args, cb)
      func(unpack(args))
    end)
  end
end

local fs_write = coroutinify(uv.fs_write)

local function get_lines_from_file(file)
  local t = {}
  for v in file:lines() do
    table.insert(t, v)
  end
  return t
end

-- can be overwritten by the user
FZF.default_window_options = {}
FZF.default_options = {
  fzf_binary      = "fzf",
  fzf_cli_args    = "",
}

-- for convenience window functions
-- currently adds a border by default
local function process_options(user_opts, window_options)

  -- backward compatibility:
  -- 'user_opts' used to be 'fzf_cli_args'
  if type(user_opts) == "string" then
    local fzf_cli_args = user_opts
    user_opts = { fzf_cli_args = fzf_cli_args }
  end

  if not user_opts then user_opts = {} end
  if not user_opts.window_options then user_opts.window_options = {} end

  -- backward compatibility:
  -- if the user supplied 'default_window_options'
  user_opts.window_options = vim.tbl_deep_extend("force",
      FZF.default_window_options, user_opts.window_options)

  -- backward compatibility: 'window_options'
  if window_options then
    user_opts.window_options = vim.tbl_deep_extend("force",
        user_opts.window_options, window_options)
  end

  -- otherwise, the border option will be passed to
  -- nvim_open_win
  if user_opts.window_options.border == false then
    user_opts.window_options.border = "none"
  elseif user_opts.window_options.border == true then
    user_opts.window_options.border = "rounded"
  elseif user_opts.window_options.border == nil then
    user_opts.window_options.border = "rounded"
  end

  -- merge the fzf binary and args
  user_opts = vim.tbl_deep_extend("force", FZF.default_options, user_opts)

  return user_opts
end

-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. The latter can use coroutines for async
-- behavior.
function FZF.raw_fzf(contents, user_opts)
  if not coroutine.running() then
    error("Please run function in a coroutine")
  end
  -- overwrite defaults if user supplied own options
  local opts = process_options(user_opts, nil)
  local command = opts.fzf_binary
  local fzf_cli_args = opts.fzf_cli_args
  local fifotmpname = vim.fn.tempname()
  local outputtmpname = vim.fn.tempname()

  if contents then
    if type(contents) == "string" and #contents>0 then
      command = string.format("%s | %s", contents, command)
    else
      command = command .. " < " .. vim.fn.shellescape(fifotmpname)
    end
  end

  if fzf_cli_args then
    command = command .. " " .. fzf_cli_args
  end

  command = command .. " > " .. vim.fn.shellescape(outputtmpname)

  vim.fn.system({'mkfifo', fifotmpname})
  local fd
  local done_state = false

  local function on_done()
    if not contents or type(contents) == "string" then
      return
    end
    if done_state then return end
    done_state = true
    uv.fs_close(fd)
  end

  local co = coroutine.running()
  vim.fn.termopen(command, {on_exit = function()
    local f = io.open(outputtmpname)
    local output = get_lines_from_file(f)
    f:close()
    on_done()
    vim.fn.delete(fifotmpname)
    vim.fn.delete(outputtmpname)
    local ret
    if #output == 0 then
      ret = nil
    else
      ret = output
    end
    coroutine.resume(co, ret)
  end})
  vim.cmd[[set ft=fzf]]
  vim.cmd[[startinsert]]


  if not contents or type(contents) == "string" then
    goto wait_for_fzf
  end

  fd = uv.fs_open(fifotmpname, "w", 0)

  -- this part runs in the background, when the user has selected, it will
  -- error out, but that doesn't matter so we just break out of the loop.
  coroutine.wrap(function ()
    if contents then
      if type(contents) == "table" then
        for _, v in ipairs(contents) do
          local err, bytes = fs_write(fd, tostring(v) .. "\n", -1)
          if err then error(err) end
        end
        on_done()
      else
        contents(function (usrval, cb)
          if done_state then return end
          if usrval == nil then
            on_done()
            if cb then cb(nil) end
            return
          end
          uv.fs_write(fd, tostring(usrval) .. "\n", -1, function (err, bytes)
            if err then
              if cb then cb(err) end
              on_done()
              return
            end

            if cb then cb(nil) end

          end)
        end, fd)
      end
    end
  end)()

  ::wait_for_fzf::

  return coroutine.yield()
end

function FZF.provided_win_fzf(contents, user_opts)
  local win = vim.api.nvim_get_current_win()
  local output = FZF.raw_fzf(contents, user_opts)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
  return output
end


function FZF.fzf(contents, user_opts, window_options)

  local opts = process_options(user_opts, window_options)

  local win = vim.api.nvim_get_current_win()
  local buf = float.create(opts.window_options)

  local results = FZF.raw_fzf(contents, opts)
  vim.api.nvim_buf_delete(buf, {force=true})
  vim.api.nvim_set_current_win(win)
  return results
end


function FZF.fzf_relative(contents, user_opts, window_options)
  window_options.relative = 'win'
  return FZF.fzf(contents, user_opts, window_options)
end


return FZF
