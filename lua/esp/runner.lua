-- Runs idf.py in a terminal panel: build errors and crash backtraces go to quickfix
local util = require("esp.util")
local board = require("esp.board")
local M = {}

-- Build errors and crash frames are also diagnostics: inline in the code, and visible to
-- Claude Code through claudecode.nvim's getDiagnostics
local ns_build = vim.api.nvim_create_namespace("esp-idf.build")
local ns_crash = vim.api.nvim_create_namespace("esp-idf.crash")
M.ns_crash = ns_crash

function M.publish(ns, items)
  vim.diagnostic.reset(ns)
  local by_buf = {}
  for _, it in ipairs(items) do
    local bufnr = (it.bufnr and it.bufnr > 0) and it.bufnr or vim.fn.bufadd(it.filename)
    by_buf[bufnr] = by_buf[bufnr] or {}
    table.insert(by_buf[bufnr], {
      lnum = it.lnum - 1,
      col = math.max((it.col or 1) - 1, 0),
      message = it.message or it.text,
      severity = it.severity
        or (it.type == "w" and vim.diagnostic.severity.WARN)
        or vim.diagnostic.severity.ERROR,
      source = "esp-idf",
    })
  end
  for bufnr, diags in pairs(by_buf) do
    vim.diagnostic.set(ns, bufnr, diags)
  end
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
  M.publish(ns_build, items)
  if #items > 0 then
    local msg = ("%d errors, %d warnings: ]q / [q to jump, Space xq to list"):format(
      errors,
      #items - errors
    )
    vim.notify("ESP-IDF " .. msg, errors > 0 and vim.log.levels.ERROR or vim.log.levels.WARN)
  end
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
  M.publish(ns_crash, {}) -- new monitor session, forget the previous crash
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
        local reason = lines[start]:match("%((.-)%)") or vim.trim(lines[start])
        for i, f in ipairs(frames) do
          local func = f.text:match("^%S+")
          f.message = i == 1 and ("Crash (%s) in %s"):format(reason, func)
            or ("Crash backtrace frame %d: %s"):format(i, func)
          f.severity = i == 1 and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN
        end
        M.publish(ns_crash, frames)
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

-- Also write a clean copy (no colors) of the output to build/<log>, overwritten per run, so
-- Claude Code can read it: monitor.log, coredump.txt. `script` keeps the command interactive.
-- Same for non-interactive commands: a pipe instead of a terminal (gdb would stop at pager prompts)
function M.with_tee(cmd, root, log)
  vim.fn.mkdir(root .. "/build", "p")
  return {
    "sh",
    "-c",
    [[(eval "$1") 2>&1 | sed -u -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\r//g' | tee "$2"]],
    "sh", -- $0: the ESP-IDF activation script only accepts being sourced from sh/bash
    cmd,
    root .. "/build/" .. log,
  }
end

function M.with_log(cmd, root, log)
  vim.fn.mkdir(root .. "/build", "p")
  local filter = [[sed -u -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\r//g' > "$2"]]
  return {
    "bash",
    "-c",
    'script -q -f -c "$1" >(' .. filter .. ")",
    "_",
    cmd,
    root .. "/build/" .. log,
  }
end

-- Only one process can hold the serial port (and one QEMU its gdb/serial sockets): starting a new
-- one stops the previous. QEMU sessions also stop when Neovim exits (idf.py qemu outlives it).
local sessions = { serial = {}, qemu = {} }

local function session_kind(args)
  if args:find("qemu") then
    return "qemu"
  elseif args:find("flash") or args:find("monitor") or args:find("erase") then
    return "serial"
  end
end

-- `script` (used for the monitor log) starts its child in a new session, so a process group kill
-- misses it: terminate every descendant instead
local function kill_tree(pid)
  for _, child in ipairs(vim.api.nvim_get_proc_children(pid)) do
    kill_tree(child)
  end
  pcall(vim.uv.kill, pid, "sigkill") -- script ignores SIGTERM and spins once its terminal is gone
end

local function stop_sessions(kind)
  for _, term in ipairs(sessions[kind]) do
    local job = vim.api.nvim_buf_is_valid(term.buf) and vim.b[term.buf].terminal_job_id
    if job and vim.fn.jobwait({ job }, 0)[1] == -1 then
      kill_tree(vim.fn.jobpid(job))
      vim.fn.jobstop(job)
      vim.fn.jobwait({ job }, 3000)
    end
    pcall(term.close, term)
  end
  sessions[kind] = {}
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    stop_sessions("qemu")
    stop_sessions("serial")
  end,
})

-- Any other command in the same panel, sharing the serial port handling
function M.term(argv, opts)
  opts = opts or {}
  if opts.uses_port then
    stop_sessions("serial")
  end
  local term = Snacks.terminal.open(argv, {
    cwd = util.project_root(),
    auto_close = false,
    win = { position = "bottom", height = 0.35 },
  })
  if opts.uses_port then
    table.insert(sessions.serial, term)
  end
  if opts.on_exit then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = vim.schedule_wrap(function()
        opts.on_exit(term.buf)
      end),
    })
  end
  return term
end

function M.idf(args, on_exit)
  local root = util.project_root()
  local port = not args:find("qemu") and board.port(root) or nil
  local cmd = util.idf_cmd((port and ("-p " .. vim.fn.shellescape(port) .. " ") or "") .. args)
  if not cmd then
    return
  end
  local since = os.time()
  local kind = session_kind(args)
  if kind then
    stop_sessions(kind)
  end
  local argv = args:find("monitor") and M.with_log(cmd, root, "monitor.log") or { "sh", "-c", cmd }
  local term = Snacks.terminal.open(argv, {
    cwd = root,
    auto_close = false,
    win = { position = "bottom", height = 0.35 },
  })
  if kind then
    table.insert(sessions[kind], term)
  end
  if args:find("monitor") then
    watch_crashes(term.buf)
  end
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = term.buf,
    once = true,
    callback = vim.schedule_wrap(function()
      -- only commands that build replace the quickfix list (a monitor keeps its crash backtrace)
      if args:find("build") or args:find("flash") or args:find("^app") or args:find("all") then
        local ok, err = pcall(load_build_errors, root, args, since)
        if not ok then
          vim.notify("ESP-IDF: could not read build log: " .. err, vim.log.levels.WARN)
        end
        -- relinked firmware: report size changes
        local map = vim.fn.glob(root .. "/build/*.map", false, true)[1]
        local st = map and vim.uv.fs_stat(map)
        if st and st.mtime.sec >= since then
          require("esp.size").after_build(root)
        end
      end
      if on_exit then
        on_exit()
      end
    end),
  })
  return term
end

return M
