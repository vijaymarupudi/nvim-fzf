local uv = vim.loop

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

-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. The latter can use coroutines for async
-- behavior.
local function raw_fzf(contents, options)
  local command = "fzf"
  local fifotmpname = vim.fn.tempname()
  local outputtmpname = vim.fn.tempname()

  if contents then
    if type(contents) == "string" then
      command = string.format("%s | %s", contents, command)
    else
      command = command .. " < " .. vim.fn.shellescape(fifotmpname)
    end
  end

  if options then
    command = command .. " " .. options
  end

  command = command .. " > " .. vim.fn.shellescape(outputtmpname)

  vim.fn.system({'mkfifo', fifotmpname})
  local fd
  local done_state = false

  local function on_done()
    if type(contents) == "string" then
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


  if type(contents) == "string" then
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
            cb(nil)
            return
          end
          uv.fs_write(fd, tostring(usrval) .. "\n", -1, function (err, bytes)
            if err then
              cb(err)
              on_done()
              return
            end

            cb(nil)
            
          end)
        end, fd)
      end
    end
  end)()

  ::wait_for_fzf::

  return coroutine.yield()
end

local function provided_win_fzf(contents, options)
  local win = vim.api.nvim_get_current_win()
  local output = raw_fzf(contents, options)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
  return output
end

local function centered_floating_window()
  return vim.fn["nvim_fzf#create_centered_window"]()
end

local fzf = function (...)
  local win = vim.api.nvim_get_current_win()
  local b1, b2 = unpack(centered_floating_window())
  local results = raw_fzf(...)
  vim.cmd("bw! " .. b1)
  vim.cmd("bw! " .. b2)
  vim.api.nvim_set_current_win(win)
  return results
end

return {
  centered_floating_window = centered_floating_window,
  provided_win_fzf = provided_win_fzf,
  raw_fzf = raw_fzf,
  fzf = fzf
}
