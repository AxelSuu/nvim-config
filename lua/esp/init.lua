-- ESP-IDF suite: `:Idf <args>` and the <leader>E keys
local runner = require("esp.runner")
local board = require("esp.board")
local tools = require("esp.tools")

vim.api.nvim_create_user_command("Idf", function(o)
  runner.idf(o.args)
end, {
  nargs = "+",
  complete = function()
    return {
      "build",
      "flash",
      "monitor",
      "openocd",
      "menuconfig",
      "size",
      "fullclean",
      "set-target",
    }
  end,
})

local function map(lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { desc = desc })
end
local function idf(args)
  return function()
    runner.idf(args)
  end
end

map("<leader>Eb", idf("build"), "Build")
map("<leader>Ef", idf("flash monitor"), "Flash and monitor")
map("<leader>Em", idf("monitor"), "Monitor")
map("<leader>Eo", idf("openocd"), "OpenOCD (for debugging)")
map("<leader>Ec", idf("menuconfig"), "Menuconfig")
map("<leader>Ep", board.pick_port, "Pick serial port")
map("<leader>Eu", board.attach_usb, "Attach USB device to WSL (usbipd)")
map("<leader>Et", tools.pick_target, "Set target chip")
map("<leader>Ea", tools.pick_action, "More idf.py actions")
map("<leader>Ed", tools.docs, "ESP-IDF docs for word under cursor")
map("<leader>En", tools.new_from_example, "New project from example")
map("<leader>EA", tools.elf_asm, "Assembly of function from built firmware")
map("<leader>EI", require("esp.ai").init_project, "Init Claude Code context (.mcp.json, CLAUDE.md)")
map("<leader>Ex", tools.run_tests, "Run hardware tests (pytest)")
map("<leader>Er", tools.add_component, "Add component from the registry")
map("<leader>Es", require("esp.size").show, "Firmware size per component")
map("<leader>EP", require("esp.partitions").show, "Partition table")
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.csv",
  callback = function(ev)
    require("esp.partitions").validate(ev.buf)
  end,
})
map("<leader>Ek", require("esp.coredump").read, "Read core dump from flash")
map("<leader>Eq", idf("qemu monitor"), "Run in QEMU (ESP32, C3, S3)")
map("<leader>EC", require("esp.config").search, "Search and change sdkconfig options")
