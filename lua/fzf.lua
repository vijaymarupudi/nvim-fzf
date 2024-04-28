local uv = vim.loop
local float = require('fzf.floating_window')
local WriteQueue = require("fzf.utils").WriteQueue

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

  opts.fzf_cli_args = opts.fzf_cli_args .. " " .. user_fzf_cli_args

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

local function generate_fzf_command(opts, contents)
  local command = opts.fzf_binary
  local fzf_cli_args = opts.fzf_cli_args
  local fifotmpname = get_temporary_pipe_name()
  local outputtmpname = vim.fn.tempname()
  local cwd = opts.fzf_cwd
  local fzf_default_command = nil

  if fzf_cli_args then
    command = command .. " " .. fzf_cli_args
  end

  if contents then
    if type(contents) == "string" and #contents>0 then
      fzf_default_command = contents
    else
      command = command .. " < " .. vim.fn.shellescape(fifotmpname)
    end
  end

  command = command .. " > " .. vim.fn.shellescape(outputtmpname)
  return command, fifotmpname, outputtmpname, cwd, fzf_default_command
end

local FZFObject = {}
FZFObject.__index = FZFObject


-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. the latter can use coroutines for async
-- behavior.
function FZFObject:new(contents, fzf_cli_args, user_options, on_complete)
  local o = {}

  -- overwrite defaults if user supplied own options
  local opts = process_options(fzf_cli_args, user_options)
  local command, fifotmpname, outputtmpname, cwd, fzf_default_command =
    generate_fzf_command(opts, contents)

  o.command = command
  o.fifotmpname = fifotmpname
  o.outputtmpname = outputtmpname
  o.cwd = cwd
  o.contents = contents
  o.fzf_default_command = fzf_default_command

  o.on_complete = on_complete
  o.write_queue = nil
  o.windows_pipe_server = nil

  setmetatable(o, self)
  return o
end

function FZFObject:cleanup(info)
  local f = io.open(self.outputtmpname)
  local output = get_lines_from_file(f)
  f:close()

  -- shell commands directly piped to fzf won't have one
  if self.write_queue then
    self.write_queue:close()
  end

  -- windows machines will use this
  if self.windows_pipe_server then
      self.windows_pipe_server:close()
  end

  -- in windows, pipes that are not used are automatically cleaned up
  if not is_windows then
    vim.fn.delete(self.fifotmpname)
  end

  vim.fn.delete(self.outputtmpname)

  -- returning to the user
  local ret
  if #output == 0 then
    ret = nil
  else
    ret = output
  end

  self.on_complete(ret, info.exit_code)
end

function FZFObject:run()


  -- Create the output pipe
  --
  -- In the Windows case, this acts like a server, which is fine. For
  -- Unix, we cannot connect yet, because opening a pipe that's disconnected on
  -- the other side will block neovim
  if is_windows then
    self.windows_pipe_server = uv.new_pipe(false)
    self.windows_pipe_server:bind(self.fifotmpname)
    self.windows_pipe_server:listen(16, function()
      local output_pipe = uv.new_pipe(false)
      self.windows_pipe_server:accept(output_pipe)
      self.write_queue = WriteQueue:new(output_pipe)
      self:handle_contents()
    end)
  else

    -- avoids $SHELL for performance reasons
    vim.fn.system({"mkfifo", self.fifotmpname})
  end

 
  local termopen_first_arg

  if is_windows then
    -- for compatibility reasons, run this command in `cmd`. This is because
    -- PowerShell does not support the `<` operator that some fzf commands use.
    termopen_first_arg = { "cmd", "/d", "/e:off", "/f:off", "/v:off", "/c", self.command }
  else
    -- for performance reasons, run this command in `sh`. This is because the
    -- default shells of some users take a long time to launch, and this
    -- creates a perceived delay that we want to avoid.
    termopen_first_arg = {"sh", "-c", self.command}
  end

  -- env should be nil if it is an empty table, this is probably a
  -- neovim/luv quirk, see discussion at
  -- https://github.com/vijaymarupudi/nvim-fzf/pull/47

  local env = nil

  if self.fzf_default_command then
     env = {
      ['FZF_DEFAULT_COMMAND'] = self.fzf_default_command,
      ['SKIM_DEFAULT_COMMAND'] = self.fzf_default_command
    }
  end

  vim.fn.termopen(termopen_first_arg, {
    cwd = self.cwd,
    env = env,
    on_exit = function(_, exit_code, _)
      self:cleanup({exit_code = exit_code})
    end
  })

  vim.cmd[[set ft=fzf]]
  vim.cmd[[startinsert]]

  if not self.contents or type(self.contents) == "string" then
    return
  end
  -- contents here is either a table or a function

  if not is_windows then
    -- have to open this after there is a reader (termopen), otherwise this
    -- will block
    local output_pipe = uv.new_pipe(false)
    local fd = uv.fs_open(self.fifotmpname, "w", -1)
    output_pipe:open(fd)
    self.write_queue = WriteQueue:new(output_pipe)
    self:handle_contents()
  end

end


function FZFObject:handle_contents()

    local async_enqueue_function = function(usrval, cb)
      if usrval == nil then
        self.write_queue:close_when_done()
      else
        self.write_queue:enqueue(tostring(usrval), cb)
      end
    end

    local async_enqueue_function_with_newline = function(usrval, cb)
      if usrval == nil then
        self.write_queue:close_when_done()
      else
        self.write_queue:enqueue({tostring(usrval), "\n"}, cb)
      end
    end

  if type(self.contents) == "table" then
    for _, v in ipairs(self.contents) do
      async_enqueue_function_with_newline(v)
    end
    async_enqueue_function_with_newline(nil)
  else

    self.contents(async_enqueue_function_with_newline,
             async_enqueue_function,
             self.write_queue.output_pipe)
  end
end


function FZF.raw_fzf(contents, fzf_cli_args, user_options)
 if not coroutine.running() then
   error("please run function in a coroutine")
 end
  local co = coroutine.running()
  local fzf_obj = FZFObject:new(contents, fzf_cli_args, user_options, function(ret, exit_code)
    coroutine.resume(co, ret, exit_code)
  end)
  
  fzf_obj:run()
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
