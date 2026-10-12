-- ESP-IDF: gdb for the chip in sdkconfig (Xtensa for esp32/s2/s3, RISC-V otherwise)
local function esp_gdb()
  local target = "esp32"
  for line in io.lines("sdkconfig") do
    local t = line:match('^CONFIG_IDF_TARGET="(.-)"')
    if t then
      target = t
      break
    end
  end
  local tools = vim.fn.expand("~/.espressif/tools")
  local pattern = target:match("^esp32s?%d?$")
      and (tools .. "/xtensa-esp-elf-gdb/*/xtensa-esp-elf-gdb/bin/xtensa-" .. target .. "-elf-gdb")
    or (tools .. "/riscv32-esp-elf-gdb/*/riscv32-esp-elf-gdb/bin/riscv32-esp-elf-gdb")
  local found = vim.fn.glob(pattern, false, true)
  return found[#found]
end

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = { "igorlfs/nvim-dap-view", "mason-org/mason.nvim" },
    keys = {
      {
        "<F5>",
        function()
          require("dap").continue()
        end,
        desc = "Debug: continue/start",
      },
      {
        "<F10>",
        function()
          require("dap").step_over()
        end,
        desc = "Debug: step over",
      },
      {
        "<F11>",
        function()
          require("dap").step_into()
        end,
        desc = "Debug: step into",
      },
      {
        "<F12>",
        function()
          require("dap").step_out()
        end,
        desc = "Debug: step out",
      },
      {
        "<leader>b",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle breakpoint",
      },
      {
        "<leader>Db",
        function()
          require("dap").set_breakpoint(vim.fn.input("Condition: "))
        end,
        desc = "Conditional breakpoint",
      },
      {
        "<leader>Dc",
        function()
          require("dap").run_to_cursor()
        end,
        desc = "Run to cursor",
      },
      {
        "<leader>Dl",
        function()
          require("dap").run_last()
        end,
        desc = "Run last",
      },
      {
        "<leader>Dt",
        function()
          require("dap").terminate()
        end,
        desc = "Terminate",
      },
      { "<leader>Dv", "<cmd>DapViewToggle<CR>", desc = "Toggle debug view" },
      { "<leader>Dw", "<cmd>DapViewWatch<CR>", mode = { "n", "x" }, desc = "Watch expression" },
    },
    config = function()
      local dap = require("dap")
      require("dap-view").setup({ auto_toggle = true })

      local registry = require("mason-registry")
      registry.refresh(function()
        local pkg = registry.get_package("codelldb")
        if not pkg:is_installed() then
          pkg:install()
        end
      end)

      dap.adapters.codelldb = {
        type = "executable",
        command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
      }
      dap.adapters.esp_gdb = function(callback)
        local gdb = esp_gdb()
        if not gdb then
          return vim.notify("No ESP gdb found under ~/.espressif/tools", vim.log.levels.ERROR)
        end
        callback({ type = "executable", command = gdb, args = { "--interpreter=dap" } })
      end

      local pick_program = function()
        return require("dap.utils").pick_file({ executables = true })
      end
      local lldb = {
        name = "Launch (codelldb)",
        type = "codelldb",
        request = "launch",
        program = pick_program,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      }
      -- Needs `idf.py openocd` running in another terminal
      local esp = {
        name = "ESP-IDF: attach via OpenOCD :3333",
        type = "esp_gdb",
        request = "attach",
        target = "localhost:3333",
        reset_halt = true,
        program = function()
          local elf = vim.fn.glob("build/*.elf", false, true)
          return elf[1] or pick_program()
        end,
      }
      -- idf.py qemu --gdb (Space Ea) waits for gdb on :3333 too, but there is no chip to reset
      local qemu = vim.tbl_extend(
        "force",
        esp,
        { name = "ESP-IDF: attach to QEMU (idf.py qemu --gdb)", reset_halt = false }
      )
      dap.configurations.c = { lldb, esp, qemu }
      dap.configurations.cpp = { lldb, esp, qemu }
      dap.configurations.rust = { vim.tbl_extend("force", lldb, { sourceLanguages = { "rust" } }) }

      -- ESP-IDF's recommended gdb startup: reset and halt the chip after attaching
      dap.listeners.after.attach.esp_reset = function(session)
        if not session.config.reset_halt then
          return
        end
        for _, cmd in ipairs({ "monitor reset halt", "maintenance flush register-cache" }) do
          session:request("evaluate", { expression = cmd, context = "repl" }, function() end)
        end
      end

      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define(
        "DapStopped",
        { text = "▶", texthl = "DiagnosticWarn", linehl = "Visual" }
      )
    end,
  },
}
