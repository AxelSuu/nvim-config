-- Target, actions menu, docs, new project from example, firmware disassembly
local util = require("esp.util")
local runner = require("esp.runner")
local M = {}

-- set-target regenerates build/ and compile_commands.json, so clangd restarts afterwards
function M.pick_target()
  local cmd = util.idf_cmd("--list-targets")
  if not cmd then
    return
  end
  vim.notify("Loading ESP-IDF targets...")
  vim.system(
    { "sh", "-c", cmd },
    { text = true },
    vim.schedule_wrap(function(res)
      local targets = vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
      local current = util.sdkconfig_target(util.project_root())
      vim.ui.select(targets, {
        prompt = "Set target (current: " .. current .. ", this wipes build/)",
      }, function(target)
        if target then
          runner.idf("set-target " .. target, function()
            vim.cmd("lsp restart clangd")
          end)
        end
      end)
    end)
  )
end

local actions = {
  { "app-flash", "Flash the app only (skips bootloader and partitions, faster)" },
  { "size", "Firmware size summary" },
  { "size-components", "Size per component" },
  { "size-files", "Size per source file" },
  { "erase-flash", "Erase the entire flash" },
  { "reconfigure", "Re-run CMake (refreshes compile_commands.json)" },
  { "save-defconfig", "Save current config as sdkconfig.defaults" },
  { "fullclean", "Delete the build directory" },
}

function M.pick_action()
  vim.ui.select(actions, {
    prompt = "idf.py",
    format_item = function(a)
      return ("%-16s %s"):format(a[1], a[2])
    end,
  }, function(a)
    if a then
      runner.idf(a[1])
    end
  end)
end

-- ESP-IDF docs search for the word under the cursor, matching IDF version and chip
function M.docs()
  local version = (util.activate_script() or ""):match("activate_idf_(v[%d.]+)%.sh") or "stable"
  local url = ("https://docs.espressif.com/projects/esp-idf/en/%s/%s/search.html?q=%s"):format(
    version,
    util.sdkconfig_target(util.project_root()),
    vim.uri_encode(vim.fn.expand("<cword>"))
  )
  vim.ui.open(url)
end

-- New project from one of the ESP-IDF examples, copied into ~/esp32/<name>
M.projects_dir = vim.fn.expand("~/esp32")

function M.new_from_example()
  local idf_path = util.idf_path()
  local examples = idf_path and (idf_path .. "/examples")
  if not examples or not vim.uv.fs_stat(examples) then
    return vim.notify("ESP-IDF examples not found", vim.log.levels.ERROR)
  end
  local list = {}
  for _, f in ipairs(vim.fn.globpath(examples, "**/main/CMakeLists.txt", false, true)) do
    local dir = f:sub(#examples + 2, -#"/main/CMakeLists.txt" - 1)
    if not dir:find("/components/") then
      list[#list + 1] = dir
    end
  end
  table.sort(list)
  require("fzf-lua").fzf_exec(list, {
    prompt = "ESP-IDF example> ",
    cwd = examples,
    preview = "batcat --style=plain --color=always {}/README.md 2>/dev/null || ls {}",
    actions = {
      default = function(selected)
        local example = selected and selected[1]
        if not example then
          return
        end
        vim.ui.input(
          { prompt = "Project name: ", default = vim.fs.basename(example) },
          function(name)
            if not name or name == "" then
              return
            end
            local dest = M.projects_dir .. "/" .. name
            if vim.uv.fs_stat(dest) then
              return vim.notify(dest .. " already exists", vim.log.levels.ERROR)
            end
            vim.fn.mkdir(M.projects_dir, "p")
            local res = vim.system({ "cp", "-r", examples .. "/" .. example, dest }):wait()
            if res.code ~= 0 then
              return vim.notify("Copy failed: " .. (res.stderr or ""), vim.log.levels.ERROR)
            end
            vim.cmd.cd(dest)
            local main = vim.fn.glob(dest .. "/main/*.c", false, true)[1]
              or vim.fn.glob(dest .. "/main/*.cpp", false, true)[1]
            if main then
              vim.cmd.edit(main)
            end
            vim.notify("Created " .. dest .. ", next: Space Et to pick the chip, then Space Eb")
          end
        )
      end,
    },
  })
end

-- Assembly of the function under the cursor as it is in the built firmware (after linking),
-- with source lines and real addresses. Space A shows the compiler output instead.
local function function_name()
  local node = vim.treesitter.get_node()
  while node and node:type() ~= "function_definition" do
    node = node:parent()
  end
  local decl = node and node:field("declarator")[1]
  while decl and decl:field("declarator")[1] do
    decl = decl:field("declarator")[1]
  end
  return decl and vim.treesitter.get_node_text(decl, 0)
end

-- Tool from the same toolchain as the compiler in compile_commands.json (objdump, size, ...)
function M.toolchain_tool(root, tool)
  local ok, head = pcall(vim.fn.readfile, root .. "/build/compile_commands.json", "", 20)
  local gcc = ok and table.concat(head, "\n"):match('"command": "(%S-g[c+][c+])%s')
  local path = gcc and gcc:gsub("g[c+][c+]$", tool)
  return path and vim.fn.executable(path) == 1 and path or nil
end

function M.elf_asm()
  local root = util.project_root()
  local name = function_name()
  local elf = vim.fn.glob(root .. "/build/*.elf", false, true)[1]
  if not name then
    return vim.notify("Cursor is not inside a function", vim.log.levels.WARN)
  end
  if not elf then
    return vim.notify("No build/*.elf yet, build first (Space Eb)", vim.log.levels.WARN)
  end
  local objdump = M.toolchain_tool(root, "objdump")
  if not objdump then
    return vim.notify("Could not find the toolchain objdump", vim.log.levels.ERROR)
  end
  if vim.uv.fs_stat(elf).mtime.sec < vim.uv.fs_stat(vim.api.nvim_buf_get_name(0)).mtime.sec then
    vim.notify("Firmware is older than this file, showing the last build", vim.log.levels.WARN)
  end
  local cmd = { objdump, "-d", "-S", "-l", "--no-show-raw-insn", "--disassemble=" .. name, elf }
  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(res)
      local lines, started = {}, false
      for _, line in ipairs(vim.split(res.stdout or "", "\n")) do
        started = started or line:match("^%x+ <") ~= nil
        if started then
          -- full source paths -> file:line
          lines[#lines + 1] = (line:gsub("^/%S+/([^/]+:%d+)$", "%1"))
        end
      end
      if #lines == 0 then
        return vim.notify(
          name .. " is not in the firmware (inlined or removed by the optimiser)",
          vim.log.levels.WARN
        )
      end
      util.show_float((" %s  ·  %s  ·  q to close "):format(name, vim.fs.basename(elf)), lines)
    end)
  )
end

return M
