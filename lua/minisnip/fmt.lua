-- fmt / fmta: build node lists from format strings (port of luasnip.extras.fmt)
local node = require("minisnip.node")
local M = {}

local function dedent(lines)
  local ind = math.huge
  for _, l in ipairs(lines) do
    local _, e = l:find("^%s*[^%s]")
    if e and e < ind then ind = e end
  end
  if ind == math.huge then return end
  for k, l in ipairs(lines) do lines[k] = l:sub(ind) end
end

local function interpolate(str, args, opts)
  local left, right = opts.delimiters:sub(1, 1), opts.delimiters:sub(2, 2)
  local pattern = "[" .. vim.pesc(left) .. vim.pesc(right) .. "]"
  local parts, used, last, pos, inside = {}, {}, 0, 0, false
  local function add_text(s) if #s > 0 then parts[#parts + 1] = s end end
  local function add_arg(ph)
    local key = tonumber(ph)
    if key then last = key
    elseif ph == "" then last = last + 1; key = last
    else key = ph end
    local a = args[key]
    assert(a, ("Missing key `%s` in format arguments: `%s`"):format(key, str))
    if used[key] then
      if opts.repeat_duplicates and a.pos then
        parts[#parts + 1] = require("minisnip.extras").rep(a.pos)
      else
        parts[#parts + 1] = vim.deepcopy(a)
      end
    else
      parts[#parts + 1], used[key] = a, true
    end
  end
  while true do
    local k = str:find(pattern, pos + 1)
    if not k then
      assert(not inside, "Missing closing delimiter: " .. str:sub(pos))
      add_text(str:sub(pos + 1))
      break
    end
    local delim = str:sub(k, k)
    if not inside and str:sub(k + 1, k + 1) == delim then
      add_text(str:sub(pos + 1, k)) -- escaped delimiter "{{" / "<<"
      pos = k + 1
    else
      assert(delim == (inside and right or left), ("Unexpected %s in format string: %s"):format(delim, str))
      if inside then add_arg(str:sub(pos + 1, k - 1)) else add_text(str:sub(pos + 1, k - 1)) end
      pos, inside = k, delim == left
    end
  end
  if opts.strict then
    for key in pairs(args) do assert(used[key], ("Unused argument: args[%s]"):format(key)) end
  end
  return parts
end

function M.format_nodes(str, nodes, opts)
  opts = vim.tbl_extend("force", { delimiters = "{}", strict = true, trim_empty = true, dedent = true }, opts or {})
  nodes = node.wrap(nodes)
  local lines = vim.split(str, "\n", { plain = true })
  if opts.trim_empty then
    if lines[1]:match("^%s*$") then table.remove(lines, 1) end
    if #lines > 0 and lines[#lines]:match("^%s*$") then lines[#lines] = nil end
  end
  if opts.dedent then dedent(lines) end
  local parts = interpolate(table.concat(lines, "\n"), nodes, opts)
  for k, p in ipairs(parts) do
    if type(p) == "string" then parts[k] = node.t(p) end
  end
  return parts
end

M.fmt = M.format_nodes
function M.fmta(str, nodes, opts)
  return M.format_nodes(str, nodes, vim.tbl_extend("force", { delimiters = "<>" }, opts or {}))
end

return M
