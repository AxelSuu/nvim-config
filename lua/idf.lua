-- ESP-IDF: `:Idf <args>` runs idf.py in a terminal with the EIM-installed environment loaded
local function activate_script()
  local found = vim.fn.glob(vim.fn.expand("~/.espressif/tools/activate_idf_v*.sh"), false, true)
  return found[#found]
end

local function idf(args)
  local script = activate_script()
  if not script then
    return vim.notify("ESP-IDF activation script not found", vim.log.levels.ERROR)
  end
  local cmd = ('. %s >/dev/null && python "$IDF_PATH/tools/idf.py" %s'):format(vim.fn.shellescape(script), args)
  Snacks.terminal.open({ "sh", "-c", cmd }, {
    cwd = vim.fs.root(0, "sdkconfig") or vim.fn.getcwd(),
    auto_close = false,
    win = { position = "bottom", height = 0.35 },
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
