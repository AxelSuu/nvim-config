-- Firmware size per component, and what changed since the previous build.
-- After each build a snapshot goes to build/nvim-size.json; Space Es shows the table.
local util = require("esp.util")
local M = {}

local function map_file(root)
  return vim.fn.glob(root .. "/build/*.map", false, true)[1]
end

local function esp_idf_size(root, args, cb)
  local map = map_file(root)
  local cmd = map
    and util.shell(
      "python -m esp_idf_size " .. args .. " --format json2 " .. vim.fn.shellescape(map)
    )
  if not cmd then
    return cb(nil)
  end
  vim.system(
    { "sh", "-c", cmd },
    { text = true },
    vim.schedule_wrap(function(res)
      local ok, data = pcall(vim.json.decode, res.stdout or "")
      cb(ok and type(data) == "table" and data or nil)
    end)
  )
end

-- archive name -> { total, flash, ram }
local function per_archive(data)
  local out = {}
  for _, a in pairs(data) do
    local flash, ram = 0, 0
    for kind, mem in pairs(a.memory_types or {}) do
      if kind:find("Flash") then
        flash = flash + mem.size
      else
        ram = ram + mem.size
      end
    end
    out[a.abbrev_name] = { total = a.size, flash = flash, ram = ram }
  end
  return out
end

local function snapshot_path(root)
  return root .. "/build/nvim-size.json"
end

local function read_snapshot(root)
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(snapshot_path(root)), "\n"))
  end)
  return ok and type(data) == "table" and data or nil
end

local function kb(n)
  return ("%.1f KB"):format(n / 1024)
end

local function signed_kb(n)
  return (n >= 0 and "+" or "") .. kb(n)
end

-- name -> delta for archives that changed (added, removed or resized)
local function deltas(cur, prev)
  local out = {}
  for name, c in pairs(cur) do
    local d = c.total - (prev[name] and prev[name].total or 0)
    if d ~= 0 then
      out[name] = d
    end
  end
  for name, p in pairs(prev) do
    if not cur[name] then
      out[name] = -p.total
    end
  end
  return out
end

local function sum(archives)
  local total = 0
  for _, a in pairs(archives) do
    total = total + a.total
  end
  return total
end

-- Called after a successful build: store the new sizes and report what changed
function M.after_build(root)
  esp_idf_size(root, "--archives", function(data)
    if not data then
      return
    end
    local cur = per_archive(data)
    local old = read_snapshot(root)
    local prev = old and old.archives or nil
    vim.fn.writefile({ vim.json.encode({ archives = cur, prev = prev }) }, snapshot_path(root))
    if not prev then
      return
    end
    local changed = deltas(cur, prev)
    local names = vim.tbl_keys(changed)
    if #names == 0 then
      return
    end
    table.sort(names, function(a, b)
      return math.abs(changed[a]) > math.abs(changed[b])
    end)
    local parts = {}
    for i = 1, math.min(3, #names) do
      parts[#parts + 1] = names[i] .. " " .. signed_kb(changed[names[i]])
    end
    local total = sum(cur)
    vim.notify(
      ("Firmware %s (%s): %s. Space Es for details"):format(
        kb(total),
        signed_kb(total - sum(prev)),
        table.concat(parts, ", ")
      )
    )
  end)
end

function M.show()
  local root = util.project_root()
  local snap = read_snapshot(root)
  if not snap then
    return vim.notify("No size data yet: build first (Space Eb)", vim.log.levels.WARN)
  end
  esp_idf_size(root, "", function(layout)
    local lines = {}
    for _, mem in ipairs(layout and layout.layout or {}) do
      local pct = mem.total > 0
          and ("  %3d%% of %s"):format(math.floor(mem.used * 100 / mem.total), kb(mem.total))
        or ""
      lines[#lines + 1] = ("%-10s %10s used%s"):format(mem.name, kb(mem.used), pct)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("%-32s %10s %10s %10s %12s"):format(
      "Component",
      "Total",
      "Flash",
      "RAM",
      "Last build"
    )
    local changed = snap.prev and deltas(snap.archives, snap.prev) or {}
    local names = vim.tbl_keys(snap.archives)
    table.sort(names, function(a, b)
      return snap.archives[a].total > snap.archives[b].total
    end)
    for _, name in ipairs(names) do
      local a = snap.archives[name]
      lines[#lines + 1] = ("%-32s %10s %10s %10s %12s"):format(
        name,
        kb(a.total),
        kb(a.flash),
        kb(a.ram),
        changed[name] and signed_kb(changed[name]) or ""
      )
    end
    for name, d in pairs(changed) do
      if not snap.archives[name] then
        lines[#lines + 1] = ("%-32s %10s %10s %10s %12s"):format(
          name .. " (removed)",
          "",
          "",
          "",
          signed_kb(d)
        )
      end
    end
    util.show_float(" Firmware size  ·  q to close ", lines, "text")
  end)
end

return M
