local uv = vim.loop
local float = require('fzf.floating_window')

local FZF = {}

local is_windows = vim.fn.has("win32") == 1

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

local DEFAULTS = {
  fzf_binary      = "fzf",
  fzf_cli_args    = "",
}

-- can be overwritten by the user
-- We cannot put the default options (above) in this object because we allow
-- users to assign a new object to this parameter.
FZF.default_options = {}

-- backwards compatibility: this was once provided as the global option object.
-- Now the options have moved beyond just windows (such as providing a binary
-- to call), so we're renaming it. This cannot be the same object as FZF.default_options because we allow users to assign a new object to this parameter.
FZF.default_window_options = {}

-- for convenience window functions
local function process_options(user_fzf_cli_args, user_options)

  if not user_fzf_cli_args then user_fzf_cli_args = "" end
  if not user_options then user_options = {} end

  local opts = vim.tbl_deep_extend("force", DEFAULTS,
    FZF.default_window_options,
    FZF.default_options,
    user_options)

  -- otherwise, the border option will be passed to
  -- nvim_open_win
  if opts.border == false then
    opts.border = "none"
  elseif opts.border == true then
    opts.border = "rounded"
  elseif opts.border == nil then
    opts.border = "rounded"
  end

  opts.fzf_cli_args = opts.fzf_cli_args .. user_fzf_cli_args

  return opts
end

local function get_temporary_pipe_name()
  if is_windows then
    local random_filename = string.gsub(vim.fn.tempname(), "/", "")
    random_filename = string.gsub(random_filename, "\\", "")
    return ([[\\.\pipe\%s]]):format(random_filename)
  else
    return vim.fn.tempname()
  end
end

-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. The latter can use coroutines for async
-- behavior.
function FZF.raw_fzf(contents, fzf_cli_args, user_options)
  if not coroutine.running() then
    error("Please run function in a coroutine")
  end
  -- overwrite defaults if user supplied own options
  local opts = process_options(fzf_cli_args, user_options)
  local command = opts.fzf_binary
  local fzf_cli_args = opts.fzf_cli_args
  local cwd = opts.fzf_cwd
  local fifotmpname = get_temporary_pipe_name()
  local outputtmpname = vim.fn.tempname()

  if fzf_cli_args then
    command = command .. " " .. fzf_cli_args
  end

  if contents then
    if type(contents) == "string" and #contents>0 then
      command = string.format("%s | %s", contents, command)
    else
      command = command .. " < " .. vim.fn.shellescape(fifotmpname)
    end
  end

  command = command .. " > " .. vim.fn.shellescape(outputtmpname)
  print(command)

  local output_pipe = nil
  local fd
  if is_windows then
    output_pipe = uv.new_pipe(false)
    uv.pipe_bind(output_pipe, fifotmpname)
    fd = uv.fileno(output_pipe)
  else
    vim.fn.system(("mkfifo %s"):format(vim.fn.shellescape(fifotmpname)))
  end

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
  vim.fn.termopen(command, {
    cwd = cwd,
    on_exit = function(_, exit_code, _)
      local f = io.open(outputtmpname)
      local output = get_lines_from_file(f)
      f:close()
      on_done()
      if is_windows then
        output_pipe:close()
      else
        vim.fn.delete(fifotmpname)
      end
      vim.fn.delete(outputtmpname)
      local ret
      if #output == 0 then
        ret = nil
      else
        ret = output
      end
      coroutine.resume(co, ret, exit_code)
    end
  })
  vim.cmd[[set ft=fzf]]
  vim.cmd[[startinsert]]


  if not contents or type(contents) == "string" then
    goto wait_for_fzf
  end

  if not is_windows then
    -- have to open this after there is a reader (termopen), otherwise this
    -- will block
    fd = uv.fs_open(fifotmpname, "w", 0)
  end


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

function FZF.provided_win_fzf(contents, fzf_cli_args, options)
  local win = vim.api.nvim_get_current_win()
  local output, exit_code = FZF.raw_fzf(contents, fzf_cli_args, options)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
  return output, exit_code
end


function FZF.fzf(contents, fzf_cli_args, options)

  local opts = process_options(fzf_cli_args, options)

  local win = vim.api.nvim_get_current_win()
  local bufnr, winid = float.create(opts)

  local results, exit_code  = FZF.raw_fzf(contents, fzf_cli_args, options)
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, {force=true})
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, {force=true})
  end
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  return results, exit_code
end


function FZF.fzf_relative(contents, fzf_cli_args, options)
  options.relative = 'win'
  return FZF.fzf(contents, fzf_cli_args, options)
end

return FZF
