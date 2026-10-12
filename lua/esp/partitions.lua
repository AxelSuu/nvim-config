-- Partition table: Space EP shows the built table against flash size and app size;
-- saving the project's custom partitions CSV validates it with gen_esp32part.py (diagnostics)
local util = require("esp.util")
local M = {}

local ns = vim.api.nvim_create_namespace("esp-idf.partitions")

local function gen_esp32part()
  local idf = util.idf_path()
  return idf and (idf .. "/components/partition_table/gen_esp32part.py")
end

local function parse_size(s)
  local n, unit = s:match("^(%d+)([KkMm]?)$")
  if n then
    return tonumber(n) * (({ k = 1024, m = 1024 * 1024 })[unit:lower()] or 1)
  end
  return tonumber(s) -- 0x...
end

local function flash_size(root)
  return parse_size((util.sdkconfig_value(root, "ESPTOOLPY_FLASHSIZE") or "4MB"):gsub("B$", ""))
end

local function kb(n)
  return n >= 1024 * 1024 and ("%.1f MB"):format(n / 1024 / 1024)
    or ("%d KB"):format(math.floor(n / 1024 + 0.5))
end

function M.show()
  local root = util.project_root()
  local bin = root .. "/build/partition_table/partition-table.bin"
  local tool = gen_esp32part()
  if not vim.uv.fs_stat(bin) or not tool then
    return vim.notify("No built partition table yet: build first (Space Eb)", vim.log.levels.WARN)
  end
  local cmd = util.shell("python " .. vim.fn.shellescape(tool) .. " " .. vim.fn.shellescape(bin))
  vim.system(
    { "sh", "-c", cmd },
    { text = true },
    vim.schedule_wrap(function(res)
      local flash = flash_size(root)
      local app_bin = vim.fn.glob(root .. "/build/*.bin", false, true)
      local app_size
      for _, f in ipairs(app_bin) do
        if not f:find("bootloader") and not f:find("partition") and not f:find("ota_data") then
          local st = vim.uv.fs_stat(f)
          app_size = app_size or (st and st.size)
        end
      end
      local width = 40
      local lines = {
        ("Flash %s  ·  app binary %s"):format(kb(flash), app_size and kb(app_size) or "not built"),
        "",
        ("%-12s %-5s %-9s %-10s %-9s %-10s %s"):format(
          "Name",
          "Type",
          "SubType",
          "Offset",
          "Size",
          "End",
          "Share of flash"
        ),
      }
      local last_end = 0
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        if not line:match("^#") then
          local f = vim.split(line, ",")
          local offset, size = tonumber(f[4] or ""), parse_size(f[5] or "")
          if offset and size then
            last_end = math.max(last_end, offset + size)
            local bar = string.rep("█", math.max(1, math.floor(size / flash * width + 0.5)))
            local note = ""
            if f[2] == "app" and app_size then
              note = ("  app uses %d%%"):format(math.floor(app_size * 100 / size))
            end
            lines[#lines + 1] = ("%-12s %-5s %-9s %-10s %-9s %-10s %s%s"):format(
              f[1],
              f[2],
              f[3],
              ("0x%x"):format(offset),
              kb(size),
              ("0x%x"):format(offset + size),
              bar,
              note
            )
          end
        end
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("Unused flash after the last partition: %s"):format(
        kb(math.max(0, flash - last_end))
      )
      util.show_float(" Partition table  ·  q to close ", lines, "text")
    end)
  )
end

-- Validate the project's custom partition CSV on save
function M.validate(buf)
  local root = util.project_root()
  local name = util.sdkconfig_value(root, "PARTITION_TABLE_CUSTOM_FILENAME")
  local file = vim.api.nvim_buf_get_name(buf)
  if not name or vim.fs.normalize(root .. "/" .. name) ~= vim.fs.normalize(file) then
    return
  end
  local size = util.sdkconfig_value(root, "ESPTOOLPY_FLASHSIZE") or "4MB"
  local cmd = util.shell(
    ("python %s --flash-size %s %s /dev/null"):format(
      vim.fn.shellescape(gen_esp32part()),
      size,
      vim.fn.shellescape(file)
    )
  )
  vim.system(
    { "sh", "-c", cmd },
    { text = true },
    vim.schedule_wrap(function(res)
      local diags = {}
      if res.code ~= 0 then
        local msg = vim.trim((res.stderr or "") .. (res.stdout or ""))
        msg = msg:gsub("Parsing CSV input%.%.%.%s*", "")
        local lnum = tonumber(msg:match("[Ll]ine (%d+)")) or 1
        diags[1] = {
          lnum = lnum - 1,
          col = 0,
          message = msg,
          severity = vim.diagnostic.severity.ERROR,
          source = "esp-idf",
        }
      end
      vim.diagnostic.set(ns, buf, diags)
    end)
  )
end

return M
