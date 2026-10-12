-- Space Ek: read the core dump saved in flash after a crash (idf.py coredump-info).
-- The crashed task's stack goes to quickfix and diagnostics, the FreeRTOS task list to a float,
-- and the full report to build/coredump.txt for Claude Code.
local util = require("esp.util")
local board = require("esp.board")
local runner = require("esp.runner")
local M = {}

local function parse(lines)
  local report = { frames = {}, tasks = {}, task = nil }
  local section
  for _, l in ipairs(lines) do
    report.task = report.task or l:match("Crashed task handle: %S+ name: '(.-)'")
    if l:match("=+ CURRENT THREAD STACK =+") then
      section = "stack"
    elseif l:match("TCB%s+NAME%s+PRIO") then
      section = "tasks"
    elseif l:match("^=+") or l:match("Id%s+Target Id") then
      section = nil
    elseif section == "stack" then
      local n, rest = l:match("^#(%d+)%s+(.*)$")
      if n then
        local func = rest:match("in (%S+) %(") or rest:match("^(%S+) %(") or rest
        local file, lnum = rest:match(" at (%S+):(%d+)$")
        report.frames[#report.frames + 1] =
          { n = tonumber(n), func = func, filename = file, lnum = tonumber(lnum) }
      end
    elseif section == "tasks" and l:match("^0x%x+") then
      report.tasks[#report.tasks + 1] = l
    end
  end
  return report
end

local function show(root, report)
  local items = {}
  for _, f in ipairs(report.frames) do
    if f.filename and vim.uv.fs_stat(f.filename) then
      items[#items + 1] = {
        filename = f.filename,
        lnum = f.lnum,
        text = ("#%d %s"):format(f.n, f.func),
        message = #items == 0
            and ("Core dump: task '%s' crashed in %s"):format(report.task or "?", f.func)
          or ("Core dump frame #%d: %s"):format(f.n, f.func),
        severity = #items == 0 and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
      }
    end
  end
  vim.fn.setqflist({}, " ", { title = "Core dump: task " .. (report.task or "?"), items = items })
  runner.publish(runner.ns_crash, items)

  local lines = { ("Crashed task: %s"):format(report.task or "?"), "", "Stack:" }
  for _, f in ipairs(report.frames) do
    lines[#lines + 1] = ("  #%d %-28s %s"):format(
      f.n,
      f.func,
      f.filename and (vim.fs.basename(f.filename) .. ":" .. f.lnum) or ""
    )
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "FreeRTOS tasks (TCB, name, prio current/base, stack used/free bytes):"
  for _, t in ipairs(report.tasks) do
    lines[#lines + 1] = "  " .. t
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "]q / [q through the stack, full report: build/coredump.txt"
  util.show_float(" Core dump  ·  q to close ", lines, "text")
end

function M.read()
  local root = util.project_root()
  if util.sdkconfig_value(root, "ESP_COREDUMP_ENABLE_TO_FLASH") ~= "y" then
    return vim.notify(
      "Core dumps to flash are off: set CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH=y (menuconfig or sdkconfig.defaults)",
      vim.log.levels.WARN
    )
  end
  local port = board.port(root)
  local cmd =
    util.idf_cmd((port and ("-p " .. vim.fn.shellescape(port) .. " ") or "") .. "coredump-info")
  if not cmd then
    return
  end
  runner.term(runner.with_tee(cmd, root, "coredump.txt"), {
    uses_port = true,
    on_exit = function()
      vim.defer_fn(function() -- let the log filter flush
        local ok, lines = pcall(vim.fn.readfile, root .. "/build/coredump.txt")
        local report = parse(ok and lines or {})
        if #report.frames == 0 then
          return vim.notify(
            "No core dump found in flash (it is saved on the next crash)",
            vim.log.levels.WARN
          )
        end
        show(root, report)
      end, 300)
    end,
  })
end

return M
