-- Space ET: live FreeRTOS task table. The nvim_task_stats component (esp/components in this config)
-- prints "TS|..." blocks; this reads the latest one from build/monitor.log and redraws every second.
local util = require("esp.util")
local M = {}

local component_dir = vim.fn.stdpath("config") .. "/esp/components/nvim_task_stats"

local function manifest(root)
  return root .. "/main/idf_component.yml"
end

local function has_component(root)
  local ok, lines = pcall(vim.fn.readfile, manifest(root))
  return ok and table.concat(lines, "\n"):find("nvim_task_stats", 1, true) ~= nil
end

local function add_component(root)
  local path = manifest(root)
  local ok, lines = pcall(vim.fn.readfile, path)
  lines = ok and lines or { "dependencies:" }
  local entry = { "  nvim_task_stats:", "    path: " .. component_dir }
  local at
  for i, l in ipairs(lines) do
    if l:match("^dependencies:") then
      at = i
    end
  end
  if not at then
    lines[#lines + 1] = "dependencies:"
    at = #lines
  end
  for i, l in ipairs(entry) do
    table.insert(lines, at + i, l)
  end
  vim.fn.writefile(lines, path)
end

-- Latest complete TS block: uptime (ms), cores, task rows
local function latest_block(root)
  local ok, lines = pcall(vim.fn.readfile, root .. "/build/monitor.log")
  if not ok then
    return nil
  end
  local stop
  for i = #lines, 1, -1 do
    if lines[i] == "TS|END" then
      stop = i
      break
    end
  end
  for i = (stop or 1) - 1, 1, -1 do
    local uptime, cores = lines[i]:match("^TS|BEGIN|(%d+)|(%d+)")
    if uptime then
      local rows = {}
      for j = i + 1, stop - 1 do
        local f = vim.split(lines[j], "|", { plain = true })
        if #f == 7 then
          rows[#rows + 1] = {
            name = f[2],
            state = f[3],
            prio = tonumber(f[4]),
            stack = tonumber(f[5]),
            cpu = tonumber(f[6]),
            core = tonumber(f[7]),
          }
        end
      end
      return { uptime = tonumber(uptime), cores = tonumber(cores), rows = rows }
    end
  end
end

local states = { X = "running", R = "ready", B = "blocked", S = "suspended", D = "deleted" }

local function render(block)
  if not block then
    return {
      "No task stats in build/monitor.log yet.",
      "",
      'Call nvim_task_stats_start(2000) in app_main (#include "nvim_task_stats.h"),',
      "then build, flash and keep the monitor open (Space Ef).",
    }
  end
  table.sort(block.rows, function(a, b)
    return a.cpu > b.cpu
  end)
  local lines = {
    ("Uptime %.1f s  ·  %d core(s)  ·  CPU %% is per core for the last period"):format(
      block.uptime / 1000,
      block.cores
    ),
    "",
    ("%-18s %-10s %5s %6s %12s %6s"):format("Task", "State", "Prio", "CPU %", "Stack free", "Core"),
  }
  for _, r in ipairs(block.rows) do
    local warn = r.stack < 512 and "  <- low stack" or ""
    lines[#lines + 1] = ("%-18s %-10s %5d %6.1f %10d B %6s%s"):format(
      r.name,
      states[r.state] or r.state,
      r.prio,
      r.cpu,
      r.stack,
      r.core < 0 and "any" or tostring(r.core),
      warn
    )
  end
  return lines
end

function M.show()
  local root = util.project_root()
  if not has_component(root) then
    return vim.ui.select({ "Yes", "No" }, {
      prompt = "Add the nvim_task_stats component to main/idf_component.yml?",
    }, function(choice)
      if choice == "Yes" then
        add_component(root)
        vim.notify(
          'Added. Now call nvim_task_stats_start(2000) in app_main (#include "nvim_task_stats.h"), build and flash'
        )
      end
    end)
  end
  local buf, win = util.show_float(
    " FreeRTOS tasks  ·  live  ·  q to close ",
    render(latest_block(root)),
    "text"
  )
  local timer = vim.uv.new_timer()
  timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if not vim.api.nvim_win_is_valid(win) then
        return timer:close()
      end
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, render(latest_block(root)))
      vim.bo[buf].modifiable = false
    end)
  )
end

return M
