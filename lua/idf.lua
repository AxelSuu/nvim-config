-- ESP-IDF: `:Idf <args>` runs idf.py in a terminal with the EIM-installed environment loaded
local function activate_script()
  local found = vim.fn.glob(vim.fn.expand("~/.espressif/tools/activate_idf_v*.sh"), false, true)
  return found[#found]
end

-- Compiler and linker messages from the build/log files idf.py writes on every run
local efm = table.concat({
  "%f:%l:%c: %trror: %m",
  "%f:%l:%c: %tarning: %m",
  "%f:%l:%c: fatal %trror: %m",
  "%f:%l:(%.%#): %m",
}, ",")

local function load_build_errors(root, args, since)
  local lines = {}
  for _, f in ipairs(vim.fn.glob(root .. "/build/log/idf_py_*_output_*", false, true)) do
    local st = vim.uv.fs_stat(f)
    if st and st.mtime.sec >= since then
      for _, l in ipairs(vim.fn.readfile(f)) do
        lines[#lines + 1] = (l:gsub("\27%[[%d;]*[mK]", ""))
      end
    end
  end
  local items, seen, errors = {}, {}, 0
  for _, it in ipairs(vim.fn.getqflist({ lines = lines, efm = efm }).items) do
    local key = it.bufnr .. ":" .. it.lnum .. ":" .. it.text
    if it.valid == 1 and not seen[key] then
      seen[key] = true
      -- linker lines ("undefined reference") carry no error/warning prefix
      it.type = it.type == "" and "e" or it.type
      items[#items + 1] = it
      errors = errors + (it.type == "e" and 1 or 0)
    end
  end
  vim.fn.setqflist({}, " ", { title = "idf.py " .. args, items = items })
  if #items > 0 then
    local msg = ("%d errors, %d warnings: ]q / [q to jump, Space xq to list"):format(errors, #items - errors)
    vim.notify("ESP-IDF " .. msg, errors > 0 and vim.log.levels.ERROR or vim.log.levels.WARN)
  end
end

local function idf(args)
  local script = activate_script()
  if not script then
    return vim.notify("ESP-IDF activation script not found", vim.log.levels.ERROR)
  end
  local root = vim.fs.root(0, "sdkconfig") or vim.fn.getcwd()
  local cmd = ('. %s >/dev/null && python "$IDF_PATH/tools/idf.py" %s'):format(vim.fn.shellescape(script), args)
  local since = os.time()
  local term = Snacks.terminal.open({ "sh", "-c", cmd }, {
    cwd = root,
    auto_close = false,
    win = { position = "bottom", height = 0.35 },
  })
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = term.buf,
    once = true,
    callback = vim.schedule_wrap(function()
      local ok, err = pcall(load_build_errors, root, args, since)
      if not ok then
        vim.notify("ESP-IDF: could not read build log: " .. err, vim.log.levels.WARN)
      end
    end),
  })
end

vim.api.nvim_create_user_command("Idf", function(o)
  idf(o.args)
end, {
  nargs = "+",
  complete = function()
    return { "build", "flash", "monitor", "openocd", "menuconfig", "size", "fullclean", "set-target" }
  end,
})

local map = function(lhs, args, desc)
  vim.keymap.set("n", lhs, function()
    idf(args)
  end, { desc = desc })
end
map("<leader>Eb", "build", "Build")
map("<leader>Ef", "flash monitor", "Flash and monitor")
map("<leader>Em", "monitor", "Monitor")
map("<leader>Eo", "openocd", "OpenOCD (for debugging)")
map("<leader>Ec", "menuconfig", "Menuconfig")
