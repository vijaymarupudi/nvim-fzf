local counter = 0
local registry = {}

local function register_func(fn)
  counter = counter + 1
  registry[counter] = fn
  -- remove from registry function
  return counter
end

local function get_func(counter)
  return registry[counter]
end

-- this is a premature optimization that can be completed after it is deemed
-- necessary.
-- local function deregister_func(counter)
--   registry[counter] = nil
-- end

return {
  register_func = register_func,
  get_func = get_func
  -- deregister_func = deregister_func
}
