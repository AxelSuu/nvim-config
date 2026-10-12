-- Serial port per project and WSL USB attach (usbipd)
local util = require("esp.util")
local M = {}

-- Remembered across sessions; idf.py autodetects when none is set
local ports_file = vim.fn.stdpath("data") .. "/idf-ports.json"

local function read_ports()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(ports_file), "\n"))
  end)
  return ok and type(data) == "table" and data or {}
end

function M.port(root)
  local port = read_ports()[root]
  return port and vim.uv.fs_stat(port) and port or nil
end

-- /dev/serial/by-id names say which board is which
function M.pick_port()
  local root = util.project_root()
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

-- Attach by VID:PID, so a changing bus id does not matter
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

function M.attach_usb()
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

return M
