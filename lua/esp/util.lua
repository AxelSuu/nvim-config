-- Shared helpers: ESP-IDF environment, project lookup, floating views
local M = {}

function M.activate_script()
  local found = vim.fn.glob(vim.fn.expand("~/.espressif/tools/activate_idf_v*.sh"), false, true)
  return found[#found]
end

function M.idf_path()
  local found = vim.fn.glob(vim.fn.expand("~/.espressif/v*/esp-idf"), false, true)
  return found[#found]
end

-- Shell command that runs idf.py (or any command) inside the ESP-IDF environment
function M.shell(cmd)
  local script = M.activate_script()
  if not script then
    vim.notify("ESP-IDF activation script not found", vim.log.levels.ERROR)
    return nil
  end
  return (". %s >/dev/null && %s"):format(vim.fn.shellescape(script), cmd)
end

function M.idf_cmd(args)
  return M.shell('python "$IDF_PATH/tools/idf.py" ' .. args)
end

function M.project_root()
  return vim.fs.root(0, "sdkconfig") or vim.fn.getcwd()
end

function M.sdkconfig_value(root, key)
  local ok, lines = pcall(vim.fn.readfile, root .. "/sdkconfig")
  for _, line in ipairs(ok and lines or {}) do
    local v = line:match("^CONFIG_" .. key .. "=(.*)$")
    if v then
      return (v:gsub('^"(.*)"$', "%1"))
    end
  end
end

function M.sdkconfig_target(root)
  return M.sdkconfig_value(root, "IDF_TARGET") or "esp32"
end

function M.show_float(title, lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or "asm"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local w = math.min(110, math.floor(vim.o.columns * 0.85))
  local h = math.min(40, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2) - 1,
    col = math.floor((vim.o.columns - w) / 2),
    border = "rounded",
    title = title,
  })
  vim.wo[win].cursorline = true
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<cmd>close<CR>", { buffer = buf, nowait = true })
  end
  return buf, win
end

return M
