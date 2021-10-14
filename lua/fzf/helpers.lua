local uv = vim.loop
local fzf_async_action = require("fzf.actions").async_action

-- save to upvalue for performance reasons
local string_byte = string.byte
local string_sub = string.sub

local function find_last_newline(str)
  for i=#str,1,-1 do
    if string_byte(str, i) == 10 then
        return i
    end
  end
end

local function process_lines(str, fn)
  return string.gsub(str, '[^\n]+', fn)
end

-- takes either a string, or a table with properties
-- cmd, the shell command to run
-- cwd, the working directory in which the command will be run
local function process_cmd_line_transformer_opts(opts)
  if type(opts) == "string" then
    opts = { cmd = opts }
  end
  return opts
end

local function cmd_line_transformer(opts, fn)

  opts = process_cmd_line_transformer_opts(opts)

  if not fn then
    fn = function (x)
      return x
    end
  end

  return function (fzf_cb)
      local stdout = uv.new_pipe(false)

      local _, pid = uv.spawn("sh", {
          args = {'-c', opts.cmd},
          stdio = {nil, stdout, nil},
          cwd = opts.cwd
      },
      -- need to specify on_exit, see:
      -- https://github.com/luvit/luv/blob/master/docs.md#uvspawnfile-options-onexit
      function()
        stdout:read_stop()
        stdout:close()
      end)

      if opts.cb_pid and type(opts.cb_pid) == 'function' then
        opts.cb_pid(pid, opts.cb_data)
      end

      local n_writing = 0
      local done = false
      local prev_line_content = nil

      local function finish()
        fzf_cb(nil, function () end)
        stdout:shutdown()
      end

      local function on_write_callback(err)
        if err then done = true end
        n_writing = n_writing - 1
        if done and n_writing == 0 then
          finish()
        end
      end

      -- the reason for this complexity is because we don't get data
      -- callbacks that neatly end with lines, we sometimes get data in between
      -- a line
      local function read_callback(err, data)
        if err then return end
        if prev_line_content then
            data = prev_line_content .. data
            prev_line_content = nil
        end
        -- eol
        if not data then
            done = true
            if n_writing == 0 then
              finish()
            end
            return
        end

        n_writing = n_writing + 1

        if string_byte(data, #data) == 10 then
            local stripped_without_newline = string_sub(data, 1, #data - 1) 
            fzf_cb(process_lines(stripped_without_newline, fn), on_write_callback)
        else
            local nl_index = find_last_newline(data)
            if not nl_index then
                prev_line_content = data
            else
                prev_line_content = string_sub(data, nl_index + 1)
                local stripped_without_newline = string_sub(data, 1, nl_index - 1)
                fzf_cb(process_lines(stripped_without_newline, fn), on_write_callback)
            end
        end
      end

      stdout:read_start(read_callback)
  end
end


local function choices_to_shell_cmd_previewer(fn, fzf_field_expression)

  local action = fzf_async_action(function(pipe, ...)

    local shell_cmd = fn(...)
    local output_pipe = uv.new_pipe(false)
    local error_pipe = uv.new_pipe(false)

    local shell = vim.env.SHELL or "sh"
    
    uv.spawn(shell, {
      args = { "-c", shell_cmd },
      stdio = { nil, output_pipe, error_pipe }
    }, function(code, signal)

    end)

    local cleaned_up = false
    local cleanup = function()
      if not cleaned_up then
        cleaned_up = true
        uv.read_stop(output_pipe)
        uv.read_stop(error_pipe)
        uv.close(output_pipe)
        uv.close(error_pipe)
        uv.close(pipe)
      end
    end

    local pending_writes = 0
    local cleanup_request_sent = false
    local cleanup_if_necessary = function()
      if pending_writes == 0 and cleanup_request_sent then
        cleanup()
      end
    end


    local read_cb = function(err, data)

      if err then
        cleanup()
        assert(not err)
      end
      if not data then
        cleanup_request_sent = true
        cleanup_if_necessary()
        return
      end

      pending_writes = pending_writes + 1

      uv.write(pipe, data, function(err)
        if err then
          cleanup()
        end
        pending_writes = pending_writes - 1
        cleanup_if_necessary()
      end)
    end

    output_pipe:read_start(read_cb)
    error_pipe:read_start(read_cb)

  end, fzf_field_expression)

  return action
end

return { 
  cmd_line_transformer = cmd_line_transformer,
  choices_to_shell_cmd_previewer = choices_to_shell_cmd_previewer
}


