local counter = 0
local registry = {}

local M = {}

function M.register_func(fn)
  counter = counter + 1
  registry[counter] = fn
  -- remove from registry function
  return counter
end

function M.get_func(counter)
  return registry[counter]
end

-- this is a premature optimization that can be completed after it is deemed
-- necessary.
-- function M.deregister_func(counter)
--   registry[counter] = nil
-- end

return M
