-- ls.parser.parse_snippet: $1, ${1}, ${1:text}, $0, escapes (\$ \} \\).
-- A repeated tabstop becomes a copy of the first one.
local node = require("minisnip.node")
local M = {}

function M.parse(body)
  local nodes, buf, seen, pos = {}, {}, {}, 1
  local function flush()
    if #buf > 0 then nodes[#nodes + 1] = node.t(table.concat(buf)); buf = {} end
  end
  local function tabstop(n, text)
    flush()
    if seen[n] and n ~= 0 then
      nodes[#nodes + 1] = require("minisnip.extras").rep(n)
    else
      seen[n] = true
      nodes[#nodes + 1] = node.i(n, text)
    end
  end
  while pos <= #body do
    local ch = body:sub(pos, pos)
    local num = body:match("^%$(%d+)", pos) or body:match("^%${(%d+)}", pos)
    local pnum, text = body:match("^%${(%d+):([^}]*)}", pos)
    if ch == "\\" and body:sub(pos + 1, pos + 1):match("[%$}\\]") then
      buf[#buf + 1] = body:sub(pos + 1, pos + 1)
      pos = pos + 2
    elseif pnum then
      tabstop(tonumber(pnum), text)
      pos = pos + 4 + #pnum + #text
    elseif num then
      tabstop(tonumber(num), "")
      pos = pos + (body:sub(pos + 1, pos + 1) == "{" and 3 or 1) + #num
    else
      buf[#buf + 1] = ch
      pos = pos + 1
    end
  end
  flush()
  return nodes
end

function M.parse_snippet(context, body)
  return require("minisnip").snippet(context, M.parse(body))
end

return M
