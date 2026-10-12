-- Format on save (conform, ESLint fixes) unless switched off globally (vim.g) or per buffer (vim.b)
local M = {}

function M.enabled(bufnr)
  local b = vim.b[bufnr or 0].autoformat
  if b ~= nil then
    return b
  end
  return vim.g.autoformat ~= false
end

function M.toggle(scope)
  return function()
    local target = scope == "buffer" and vim.b or vim.g
    target.autoformat = not M.enabled()
    vim.notify(("Format on save %s (%s)"):format(target.autoformat and "on" or "off", scope))
  end
end

return M
