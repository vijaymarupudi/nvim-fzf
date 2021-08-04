local uv = vim.loop
local fzf_async_action = require("fzf.actions").async_action

local function find_last_newline(str)
  for i=#str,1,-1 do
    if string.byte(str, i) == 10 then
        return i
    end
  end
end

local function process_lines(str, fn)
  local t = {}
  local lines = vim.split(str, "\n")
  for idx, val in ipairs(lines) do
      t[idx] = fn(val)
  end
  return table.concat(t, "\n")
end

local function cmd_line_transformer(cmd, fn)

  if not fn then
    fn = function (x)
      return x
    end
  end

  return function (fzf_cb)
      local stdout = uv.new_pipe(false)

      uv.spawn("sh", {
          args = {'-c', cmd},
          stdio = {nil, stdout, nil}
      },
      -- need to specify on_exit, see:
      -- https://github.com/luvit/luv/blob/master/docs.md#uvspawnfile-options-onexit
      function()
        stdout:read_stop()
        stdout:close()
      end)

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

        if string.byte(data, #data) == 10 then
            local stripped_without_newline = string.sub(data, 1, #data - 1) 
            fzf_cb(process_lines(stripped_without_newline, fn), on_write_callback)
        else
            local nl_index = find_last_newline(data)
            prev_line_content = string.sub(data, nl_index + 1)
            local stripped_without_newline = string.sub(data, 1, nl_index - 1)
            fzf_cb(process_lines(stripped_without_newline, fn), on_write_callback)
        end
      end

      stdout:read_start(read_callback)
  end
end


local function choices_to_shell_cmd_previewer(fn)

  local action = fzf_async_action(function(pipe, ...)

    local shell_cmd = fn(...)
    local output_pipe = uv.new_pipe()
    local error_pipe = uv.new_pipe()

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

    local read_cb = function(err, data)

      if err then
        cleanup()
        assert(not err)
      end
      if not data then
        cleanup()
        return
      end

      uv.write(pipe, data, function(err)
        if err then
          cleanup()
        end
      end)
    end

    output_pipe:read_start(read_cb)
    error_pipe:read_start(read_cb)

  end)

  return action
end

return { 
  cmd_line_transformer = cmd_line_transformer,
  choices_to_shell_cmd_previewer = choices_to_shell_cmd_previewer
}


