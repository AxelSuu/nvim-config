-- Space EC: search all sdkconfig options (title, help, current value) and change them without
-- menuconfig. Writes sdkconfig like menuconfig does, then `idf.py reconfigure` validates it.
local util = require("esp.util")
local runner = require("esp.runner")
local M = {}

local function read_json(path)
  local ok, data = pcall(function()
    return vim.json.decode(
      table.concat(vim.fn.readfile(path), "\n"),
      { luanil = { object = true, array = true } }
    )
  end)
  return ok and data or nil
end

-- name -> option, with the menu path that leads to it
local function options(root)
  local menus = read_json(root .. "/build/config/kconfig_menus.json")
  local values = read_json(root .. "/build/config/sdkconfig.json") or {}
  if not menus then
    return nil
  end
  local out = {}
  local function walk(nodes, path)
    for _, n in ipairs(nodes) do
      if n.name and n.type ~= "menu" and n.type ~= "choice" then
        out[n.name] = {
          name = n.name,
          title = n.title or "",
          help = n.help,
          type = n.type,
          range = n.range,
          depends_on = n.depends_on,
          path = table.concat(path, " > "),
          value = values[n.name],
        }
      end
      local sub = vim.list_extend({}, path)
      if n.title and (n.type == "menu" or n.type == "choice" or n.children and #n.children > 0) then
        sub[#sub + 1] = n.title
      end
      walk(n.children or {}, sub)
    end
  end
  walk(menus, {})
  return out
end

local function show_value(o)
  if o.type == "bool" then
    return o.value and "y" or "n"
  end
  return o.value == nil and "-" or tostring(o.value)
end

-- Set CONFIG_<name> in sdkconfig (bool false is "# CONFIG_X is not set")
local function write_values(root, changes)
  local path = root .. "/sdkconfig"
  local lines = vim.fn.readfile(path)
  for name, line in pairs(changes) do
    local found = false
    for i, l in ipairs(lines) do
      if l:match("^CONFIG_" .. name .. "=") or l == ("# CONFIG_" .. name .. " is not set") then
        lines[i], found = line, true
      end
    end
    if not found then
      lines[#lines + 1] = line
    end
  end
  vim.fn.writefile(lines, path)
end

local function config_line(o, value)
  if o.type == "bool" then
    return value and ("CONFIG_%s=y"):format(o.name) or ("# CONFIG_%s is not set"):format(o.name)
  elseif o.type == "string" then
    return ('CONFIG_%s="%s"'):format(o.name, value)
  end
  return ("CONFIG_%s=%s"):format(o.name, value)
end

local function apply(root, opts, o)
  local changes = {}
  if o.type == "bool" then
    local choice = (o.depends_on or ""):match("^<choice (%S+)>$")
    if choice then
      -- a choice option: select it and clear its siblings
      for _, other in pairs(opts) do
        if other.depends_on == o.depends_on then
          changes[other.name] = config_line(other, other.name == o.name)
        end
      end
    else
      changes[o.name] = config_line(o, not o.value)
    end
    write_values(root, changes)
    return runner.idf("reconfigure")
  end
  vim.ui.input({
    prompt = ("%s (%s%s): "):format(
      o.name,
      o.type,
      o.range and (" " .. o.range[1] .. ".." .. o.range[2]) or ""
    ),
    default = show_value(o),
  }, function(v)
    if not v or v == "" then
      return
    end
    write_values(root, { [o.name] = config_line(o, v) })
    runner.idf("reconfigure")
  end)
end

function M.search()
  local root = util.project_root()
  local opts = options(root)
  if not opts then
    return vim.notify(
      "No build/config yet: build or reconfigure first (Space Eb)",
      vim.log.levels.WARN
    )
  end
  local names = vim.tbl_keys(opts)
  table.sort(names)
  local entries = {}
  for _, name in ipairs(names) do
    local o = opts[name]
    entries[#entries + 1] = ("%s\t%s\t%s\t%s"):format(name, show_value(o), o.title, o.path)
  end
  require("fzf-lua").fzf_exec(entries, {
    prompt = "sdkconfig> ",
    fzf_opts = { ["--delimiter"] = "\t", ["--tabstop"] = "2" },
    preview = function(selected)
      local o = opts[vim.split(selected[1], "\t")[1]]
      if not o then
        return ""
      end
      local lines = {
        "CONFIG_" .. o.name .. " = " .. show_value(o),
        o.title,
        "type: "
          .. tostring(o.type)
          .. (o.range and ("  range: " .. o.range[1] .. ".." .. o.range[2]) or ""),
        "menu: " .. o.path,
      }
      if o.depends_on then
        lines[#lines + 1] = "depends on: " .. o.depends_on
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = o.help or "(no help text)"
      return table.concat(lines, "\n")
    end,
    actions = {
      default = function(selected)
        local o = selected and selected[1] and opts[vim.split(selected[1], "\t")[1]]
        if o then
          apply(root, opts, o)
        end
      end,
    },
  })
end

return M
