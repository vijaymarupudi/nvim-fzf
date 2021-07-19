local uv = vim.loop

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

return { 
  cmd_line_transformer = cmd_line_transformer
}
