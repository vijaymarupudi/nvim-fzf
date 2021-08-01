print = function(...)
  io.stdout:write(table.concat({...}, "\t") .. "\n")
end
local function_id = tonumber(vim.fn.argv(1))
local success, errmsg = pcall(function ()
  -- this is guaranteed to be 2 or more, we are interested in those greater than 2
  local nargs = vim.fn.argc()
  local args = {}
  for i=3,nargs do
    -- vim uses zero indexing
    table.insert(args, vim.fn.argv(i - 1))
  end
  local environ = vim.fn.environ()
  local chan_id = vim.fn.sockconnect("pipe", environ.NVIM_LISTEN_ADDRESS, { rpc = true })
  local preview_lines = environ.FZF_PREVIEW_LINES or environ.LINES
  local preview_cols = environ.FZF_PREVIEW_COLUMNS or environ.COLUMNS
  local usrresult = vim.rpcrequest(chan_id, "nvim_exec_lua", [[
    local luaargs = {...}
    local function_id = luaargs[1]
    local fzf_selection = luaargs[2]
    local fzf_lines = luaargs[3]
    local fzf_columns = luaargs[4]
    local usr_func = require"fzf.registry".get_func(function_id)
    return usr_func(fzf_selection, fzf_lines, fzf_columns)
  ]], {function_id, args, tonumber(preview_lines), tonumber(preview_cols)})

  if type(usrresult) == "string" then
    print(usrresult)
  elseif type(usrresult) == "table" then
    print(table.concat(usrresult, "\n"))
  elseif usrresult == vim.NIL then
    -- do nothing
  else
    error("Invalid user function return type")
  end
  vim.fn.chanclose(chan_id)
end)
if not success then
  print("ERROR: " .. errmsg)
end

vim.cmd [[qall]]
