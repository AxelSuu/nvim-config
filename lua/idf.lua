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
