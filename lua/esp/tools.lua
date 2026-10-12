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
  { "qemu --gdb monitor", "Run in QEMU waiting for the debugger (then F5: attach to QEMU)" },
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

-- Hardware-in-the-loop tests: bin/esp-test builds and runs the project's pytest_*.py on the board
function M.run_tests()
  local root = util.project_root()
  if #vim.fn.glob(root .. "/pytest_*.py", false, true) == 0 then
    return vim.notify("No pytest_*.py in " .. root, vim.log.levels.WARN)
  end
  local argv = { vim.fn.stdpath("config") .. "/bin/esp-test" }
  local port = require("esp.board").port(root)
  if port then
    argv[2] = port
  end
  runner.term(argv, {
    uses_port = true,
    on_exit = function(buf)
      local summary
      for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        summary = l:match("=+ (.-%d+ %a+.-) =+") or summary
      end
      local failed = not summary or summary:find("failed") or summary:find("error")
      vim.notify(
        "ESP tests: " .. (summary or "did not run, see the panel"),
        failed and vim.log.levels.ERROR or nil
      )
    end,
  })
end

-- Component registry: search, README preview, add-dependency, reconfigure (downloads it)
function M.add_component()
  vim.ui.input({ prompt = "Search ESP components: " }, function(query)
    if not query or query == "" then
      return
    end
    local url = "https://components.espressif.com/api/components?per_page=50&q="
      .. vim.uri_encode(query)
    vim.system(
      { "curl", "-sf", "-m", "20", url },
      { text = true },
      vim.schedule_wrap(function(res)
        local ok, list = pcall(vim.json.decode, res.stdout or "")
        if res.code ~= 0 or not ok or type(list) ~= "table" or #list == 0 then
          return vim.notify("No components found for " .. query, vim.log.levels.WARN)
        end
        local entries = {}
        for _, c in ipairs(list) do
          local v = c.latest_version or {}
          local desc = (v.description or ""):gsub("[\t\n]", " ")
          local readme = v.docs and v.docs.readme or ""
          entries[#entries + 1] =
            table.concat({ c.namespace .. "/" .. c.name, v.version or "?", desc, readme }, "\t")
        end
        require("fzf-lua").fzf_exec(entries, {
          prompt = "Component> ",
          fzf_opts = { ["--delimiter"] = "\t", ["--with-nth"] = "1..3" },
          preview = "curl -sf -m 10 {4} | batcat --style=plain --color=always -l md",
          actions = {
            default = function(selected)
              local fields = selected and selected[1] and vim.split(selected[1], "\t")
              if not fields then
                return
              end
              local spec = ('"%s^%s"'):format(fields[1], (fields[2]:gsub("~.*$", "")))
              runner.idf("add-dependency " .. spec, function()
                runner.idf("reconfigure", function()
                  vim.cmd("lsp restart clangd")
                  vim.notify(
                    "Added " .. fields[1] .. " " .. fields[2] .. " (main/idf_component.yml)"
                  )
                end)
              end)
            end,
          },
        })
      end)
    )
  end)
end

-- Project-wide clang-tidy (idf.py clang-check writes warnings.txt): quickfix and diagnostics,
-- only for files in the project (ESP-IDF's own sources are skipped)
local ns_tidy = vim.api.nvim_create_namespace("esp-idf.tidy")

function M.clang_check()
  local root = util.project_root()
  runner.idf("clang-check", function()
    local ok, lines = pcall(vim.fn.readfile, root .. "/warnings.txt")
    if not ok then
      return vim.notify("clang-check wrote no warnings.txt, see the panel", vim.log.levels.WARN)
    end
    local items, seen = {}, {}
    local efm = "%f:%l:%c: %trror: %m,%f:%l:%c: %tarning: %m"
    for _, it in ipairs(vim.fn.getqflist({ lines = lines, efm = efm }).items) do
      local file = it.bufnr > 0 and vim.api.nvim_buf_get_name(it.bufnr) or ""
      local key = file .. ":" .. it.lnum .. ":" .. it.text
      if
        it.valid == 1
        and vim.startswith(file, root .. "/")
        and not file:find("/managed_components/")
        and not seen[key]
      then
        seen[key] = true
        items[#items + 1] = it
      end
    end
    vim.fn.setqflist({}, " ", { title = "clang-tidy", items = items })
    vim.diagnostic.reset(ns_tidy)
    local by_buf = {}
    for _, it in ipairs(items) do
      by_buf[it.bufnr] = by_buf[it.bufnr] or {}
      table.insert(by_buf[it.bufnr], {
        lnum = it.lnum - 1,
        col = math.max(it.col - 1, 0),
        message = it.text,
        severity = it.type == "e" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
        source = "clang-tidy",
      })
    end
    for bufnr, diags in pairs(by_buf) do
      vim.diagnostic.set(ns_tidy, bufnr, diags)
    end
    vim.notify(("clang-tidy: %d findings in the project (]q / Space xq)"):format(#items))
  end)
end

return M
