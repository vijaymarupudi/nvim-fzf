local WriteQueue = {}
WriteQueue.__index = WriteQueue

function WriteQueue:new(output_pipe)
  local q = {
    done_state = false,
    output_pipe = output_pipe,
    n_enqueued = 0,
    close_when_done_flag = false
  }
  setmetatable(q, self)
  return q
end

function WriteQueue:close()
  if not self.done_state then
    self.done_state = true
    -- in case the user has closed the pipe first, we don't want the double
    -- close error to propagate.
    pcall(function()
      self.output_pipe:close()
    end)
  end
end

function WriteQueue:close_when_done()
  self.close_when_done_flag = true
  if self.n_enqueued == 0 then
    self:close()
  end
end

function WriteQueue:enqueue(input, cb)
  if self.done_state then
    if cb then cb("PIPE closed") end
    return nil
  end
  self.n_enqueued = self.n_enqueued + 1
  self.output_pipe:write(input, function(err)
    if err then
      self:close()
      if cb then cb(err) end
      return nil
    end
    self.n_enqueued = self.n_enqueued - 1
    if self.n_enqueued == 0 and self.close_when_done_flag then
      self:close()
    end
    if cb then cb(nil) end
  end)
end

return { WriteQueue = WriteQueue }
