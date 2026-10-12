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
    local msg = ("%d errors, %d warnings: ]q / [q to jump, Space xq to list"):format(
      errors,
      #items - errors
    )
    vim.notify("ESP-IDF " .. msg, errors > 0 and vim.log.levels.ERROR or vim.log.levels.WARN)
  end
end

-- Serial port per project, remembered across sessions; idf.py autodetects when none is set
local ports_file = vim.fn.stdpath("data") .. "/idf-ports.json"

local function read_ports()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(ports_file), "\n"))
  end)
  return ok and type(data) == "table" and data or {}
end

local function project_root()
  return vim.fs.root(0, "sdkconfig") or vim.fn.getcwd()
end

local function project_port(root)
  local port = read_ports()[root]
  return port and vim.uv.fs_stat(port) and port or nil
end

-- Monitor: on a crash the monitor prints decoded frames ("--- 0x4000afce: app_main at /p/main.c:18").
-- They go into the quickfix list as soon as they appear, while the monitor keeps running.
local crash_markers =
  { "Guru Meditation", "abort%(%) was called", "assert failed", "Stack smashing" }

local function crash_frames(lines, start)
  local frames, entry = {}, nil
  local function flush()
    local addr, func, file, lnum = (entry or ""):match("^%-%-%- (0x%x+): (.-) at (%S+):(%d+)")
    if addr and vim.uv.fs_stat(file) then
      frames[#frames + 1] = { filename = file, lnum = tonumber(lnum), text = func .. "  " .. addr }
    end
    entry = nil
  end
  for i = start, #lines do
    local l = lines[i]
    if l:match("^%-%-%- 0x") then
      flush()
      entry = l
    elseif entry and not entry:match(":%d+%s*$") then
      entry = entry .. vim.trim(l) -- terminal wrapped a long line
    else
      flush()
    end
  end
  flush()
  return frames
end

local function watch_crashes(buf)
  local pending, notified = false, nil
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if pending then
        return
      end
      pending = true
      vim.defer_fn(function()
        pending = false
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local start
        for i = #lines, 1, -1 do
          for _, marker in ipairs(crash_markers) do
            if lines[i]:find(marker) then
              start = i
            end
          end
          if start then
            break
          end
        end
        local frames = start and crash_frames(lines, start) or {}
        if #frames == 0 then
          return
        end
        vim.fn.setqflist(
          {},
          " ",
          { title = "ESP crash: " .. vim.trim(lines[start]), items = frames }
        )
        -- a crash loop repeats the same crash after every reboot; say it once
        local key = frames[1].filename .. ":" .. frames[1].lnum
        if key ~= notified then
          notified = key
          local f = frames[1]
          vim.notify(
            ("ESP crashed in %s (%s:%d): ]q / [q through the backtrace, Space xq to list"):format(
              f.text:match("^%S+"),
              vim.fs.basename(f.filename),
              f.lnum
            ),
            vim.log.levels.ERROR
          )
        end
      end, 700)
    end,
  })
end

local function idf(args, on_exit)
  local script = activate_script()
  if not script then
    return vim.notify("ESP-IDF activation script not found", vim.log.levels.ERROR)
  end
  local root = project_root()
  local port = project_port(root)
  local port_arg = port and ("-p " .. vim.fn.shellescape(port) .. " ") or ""
  local cmd = ('. %s >/dev/null && python "$IDF_PATH/tools/idf.py" %s%s'):format(
    vim.fn.shellescape(script),
    port_arg,
    args
  )
  local since = os.time()
  local term = Snacks.terminal.open({ "sh", "-c", cmd }, {
    cwd = root,
    auto_close = false,
    win = { position = "bottom", height = 0.35 },
  })
  if args:find("monitor") then
    watch_crashes(term.buf)
  end
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = term.buf,
    once = true,
    callback = vim.schedule_wrap(function()
      local ok, err = pcall(load_build_errors, root, args, since)
      if not ok then
        vim.notify("ESP-IDF: could not read build log: " .. err, vim.log.levels.WARN)
      end
      if on_exit then
        on_exit()
      end
    end),
  })
end

-- Serial port picker; /dev/serial/by-id names say which board is which
local function pick_port()
  local root = project_root()
  local choices = {}
  for _, link in ipairs(vim.fn.glob("/dev/serial/by-id/*", false, true)) do
    choices[#choices + 1] = { port = vim.uv.fs_realpath(link), label = vim.fs.basename(link) }
  end
  if #choices == 0 then
    for _, dev in ipairs(vim.fn.glob("/dev/tty{USB,ACM}*", false, true)) do
      choices[#choices + 1] = { port = dev, label = dev }
    end
  end
  choices[#choices + 1] = { label = "Auto-detect (let idf.py choose)" }
  vim.ui.select(choices, {
    prompt = "Serial port for " .. vim.fs.basename(root),
    format_item = function(c)
      return c.port and (c.port .. "  " .. c.label) or c.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    local ports = read_ports()
    ports[root] = choice.port
    vim.fn.writefile({ vim.json.encode(ports) }, ports_file)
    vim.notify("ESP-IDF port: " .. (choice.port or "auto-detect"))
  end)
end

-- WSL: attach a USB device with usbipd by VID:PID, so a changing bus id does not matter
local serial_vids =
  { ["303a"] = "Espressif", ["1a86"] = "WCH CH34x", ["10c4"] = "Silabs CP210x", ["0403"] = "FTDI" }

local function usb_devices()
  local res = vim.system({ "usbipd.exe", "list" }, { text = true }):wait()
  local devices, connected = {}, false
  for line in (res.stdout or ""):gsub("\r", ""):gmatch("[^\n]+") do
    if line:match("^Connected:") then
      connected = true
    elseif line:match("^Persisted:") then
      connected = false
    elseif connected then
      local busid, vid, pid, rest = line:match("^(%d+%-%d+)%s+(%x+):(%x+)%s+(.-)%s*$")
      if busid then
        local state = rest:match("(Not shared)$")
          or rest:match("(Shared)$")
          or rest:match("(Attached)$")
          or ""
        devices[#devices + 1] = {
          busid = busid,
          hwid = vid:lower() .. ":" .. pid:lower(),
          vendor = serial_vids[vid:lower()],
          desc = vim.trim(rest:sub(1, #rest - #state)),
          state = state,
        }
      end
    end
  end
  table.sort(devices, function(a, b)
    return (a.vendor and 0 or 1) < (b.vendor and 0 or 1)
  end)
  return devices
end

local function attach_usb()
  if vim.fn.executable("usbipd.exe") == 0 then
    return vim.notify("usbipd.exe not found (install usbipd-win on Windows)", vim.log.levels.ERROR)
  end
  vim.ui.select(usb_devices(), {
    prompt = "Attach USB device to WSL",
    format_item = function(d)
      return ("%s  %s  %s  [%s]"):format(
        d.hwid,
        d.vendor and ("(" .. d.vendor .. ")") or "",
        d.desc,
        d.state
      )
    end,
  }, function(d)
    if not d then
      return
    end
    if d.state == "Attached" then
      return vim.notify(d.desc .. " is already attached")
    end
    local function attach()
      vim.fn.jobstart(
        { "usbipd.exe", "attach", "--wsl", "--hardware-id", d.hwid, "--auto-attach" },
        { detach = true }
      )
      vim.notify("Attaching " .. d.desc .. " (stays attached across resets and replugs)")
    end
    if d.state == "Not shared" then
      -- binding needs admin once per device; Windows shows a UAC prompt
      vim.notify("Sharing " .. d.desc .. " with WSL, accept the Windows admin prompt")
      vim.system({
        "powershell.exe",
        "-NoProfile",
        "-Command",
        ("Start-Process usbipd -ArgumentList 'bind','--hardware-id','%s' -Verb RunAs -Wait"):format(
          d.hwid
        ),
      }, {}, vim.schedule_wrap(attach))
    else
      attach()
    end
  end)
end

local function sdkconfig_target(root)
  local ok, lines = pcall(vim.fn.readfile, root .. "/sdkconfig")
  for _, line in ipairs(ok and lines or {}) do
    local t = line:match('^CONFIG_IDF_TARGET="(.-)"')
    if t then
      return t
    end
  end
  return "esp32"
end

-- set-target regenerates build/ and compile_commands.json, so clangd restarts afterwards
local function pick_target()
  local script = activate_script()
  if not script then
    return
  end
  vim.notify("Loading ESP-IDF targets...")
  local cmd = ('. %s >/dev/null && python "$IDF_PATH/tools/idf.py" --list-targets'):format(
    vim.fn.shellescape(script)
  )
  vim.system(
    { "sh", "-c", cmd },
    { text = true },
    vim.schedule_wrap(function(res)
      local targets = vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
      local current = sdkconfig_target(project_root())
      vim.ui.select(targets, {
        prompt = "Set target (current: " .. current .. ", this wipes build/)",
      }, function(target)
        if target then
          idf("set-target " .. target, function()
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

local function pick_action()
  vim.ui.select(actions, {
    prompt = "idf.py",
    format_item = function(a)
      return ("%-16s %s"):format(a[1], a[2])
    end,
  }, function(a)
    if a then
      idf(a[1])
    end
  end)
end

-- ESP-IDF docs search for the word under the cursor, matching IDF version and chip
local function docs()
  local version = (activate_script() or ""):match("activate_idf_(v[%d.]+)%.sh") or "stable"
  local url = ("https://docs.espressif.com/projects/esp-idf/en/%s/%s/search.html?q=%s"):format(
    version,
    sdkconfig_target(project_root()),
    vim.uri_encode(vim.fn.expand("<cword>"))
  )
  vim.ui.open(url)
end

-- New project from one of the ESP-IDF examples, copied into ~/esp32/<name>
local projects_dir = vim.fn.expand("~/esp32")

local function new_from_example()
  local idf_path = vim.fn.glob(vim.fn.expand("~/.espressif/v*/esp-idf"), false, true)
  local examples = idf_path[#idf_path] and (idf_path[#idf_path] .. "/examples")
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
            local dest = projects_dir .. "/" .. name
            if vim.uv.fs_stat(dest) then
              return vim.notify(dest .. " already exists", vim.log.levels.ERROR)
            end
            vim.fn.mkdir(projects_dir, "p")
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

local function show_float(title, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "asm"
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
end

local function elf_asm()
  local root = project_root()
  local name = function_name()
  local elf = vim.fn.glob(root .. "/build/*.elf", false, true)[1]
  if not name then
    return vim.notify("Cursor is not inside a function", vim.log.levels.WARN)
  end
  if not elf then
    return vim.notify("No build/*.elf yet, build first (Space Eb)", vim.log.levels.WARN)
  end
  -- objdump from the same toolchain as the compiler in compile_commands.json
  local ok, head = pcall(vim.fn.readfile, root .. "/build/compile_commands.json", "", 20)
  local gcc = ok and table.concat(head, "\n"):match('"command": "(%S-g[c+][c+])%s')
  local objdump = gcc and gcc:gsub("g[c+][c+]$", "objdump")
  if not objdump or vim.fn.executable(objdump) == 0 then
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
      show_float((" %s  ·  %s  ·  q to close "):format(name, vim.fs.basename(elf)), lines)
    end)
  )
end

vim.api.nvim_create_user_command("Idf", function(o)
  idf(o.args)
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
vim.keymap.set("n", "<leader>Ep", pick_port, { desc = "Pick serial port" })
vim.keymap.set("n", "<leader>Eu", attach_usb, { desc = "Attach USB device to WSL (usbipd)" })
vim.keymap.set("n", "<leader>Et", pick_target, { desc = "Set target chip" })
vim.keymap.set("n", "<leader>Ea", pick_action, { desc = "More idf.py actions" })
vim.keymap.set("n", "<leader>Ed", docs, { desc = "ESP-IDF docs for word under cursor" })
vim.keymap.set("n", "<leader>En", new_from_example, { desc = "New project from example" })
vim.keymap.set("n", "<leader>EA", elf_asm, { desc = "Assembly of function from built firmware" })
