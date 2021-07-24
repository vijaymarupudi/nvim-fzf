local M = {}


-- Create a centered floating window
function M.create(opts)
  local relative = opts.relative or 'editor'
  local columns, lines = vim.o.columns, vim.o.lines
  if relative == 'win' then
    columns, lines = vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0)
  end

  local win_opts = {
    width = opts.width or math.min(columns - 4, math.max(80, columns - 20)),
    height = opts.height or math.min(lines - 4, math.max(20, lines - 10)),
    style = 'minimal',
    relative = relative,
    border = opts.border
  }
  win_opts.row = opts.row or math.floor(((lines - win_opts.height) / 2) - 1)
  win_opts.col = opts.col or math.floor((columns - win_opts.width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)

  if opts.window_on_create then
    opts.window_on_create()
  end

  return bufnr, winid
end

return M
