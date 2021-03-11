local M = {}

-- Create a centered floating window
function M.create_absolute(width, height)
  local columns, lines = vim.o.columns, vim.o.lines

  if not width then
    width = math.min(columns - 4, math.max(80, columns - 20))
  end

  if not height then
    height = math.min(lines - 4, math.max(20, lines - 10))
  end

  local top = math.floor(((lines - height) / 2) - 1)
  local left = math.floor((columns - width) / 2)

  local opts = { relative = 'editor', row = top, col = left, width = width, height = height, style = 'minimal' }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(bufnr, true, opts)

  -- setting background to the normal background color
  vim.cmd [[set winhl=Normal:Normal]]

  return bufnr
end

-- Create a centered floating window relative to the current split
function M.create_relative(width, height)
  local columns, lines = vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0)
  local row, col = unpack(vim.api.nvim_win_get_position(0))

  if not width then
    width = math.min(columns - 4, math.max(80, columns - 20))
  end

  if not height then
    height = math.min(lines - 4, math.max(20, lines - 10))
  end

  local top = math.floor((row + (lines / 2)) - (height / 2))
  local left = math.floor((col + (columns / 2)) - (width / 2))

  local opts = { relative = 'editor', row = top, col = left, width = width, height = height, style = 'minimal' }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(bufnr, true, opts)

  -- setting background to the normal background color
  vim.cmd [[set winhl=Normal:Normal]]

  return bufnr
end

return M
