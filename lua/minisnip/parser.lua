-- Minimal LSP/VSCode snippet body parser: $1 ${1} ${1:text} ${1|a,b|} $0 $VAR ${VAR:default}
local node = require("minisnip.node")
local M = {}

local VARS = {
  TM_FILENAME = function() return vim.fn.expand("%:t") end,
  TM_FILENAME_BASE = function() return vim.fn.expand("%:t:r") end,
  TM_FILEPATH = function() return vim.fn.expand("%:p") end,
  TM_DIRECTORY = function() return vim.fn.expand("%:p:h") end,
  TM_LINE_NUMBER = function() return tostring(vim.fn.line(".")) end,
  TM_CURRENT_LINE = function() return vim.api.nvim_get_current_line() end,
  TM_CURRENT_WORD = function() return vim.fn.expand("<cword>") end,
  CURRENT_YEAR = function() return os.date("%Y") end,
  CURRENT_MONTH = function() return os.date("%m") end,
  CURRENT_DATE = function() return os.date("%d") end,
  CURRENT_HOUR = function() return os.date("%H") end,
  CURRENT_MINUTE = function() return os.date("%M") end,
  CURRENT_SECOND = function() return os.date("%S") end,
}
function M.var(name)
  local f = VARS[name]
  return f and f() or nil
end

local function flatten(nodes)
  local out = {}
  for _, n in ipairs(nodes) do
    if n.text then out[#out + 1] = table.concat(n.text, "\n") end
  end
  return table.concat(out)
end

function M.parse(body)
  local pos, seen = 1, {}

  local function tabstop(n, nodes)
    if seen[n] and n ~= 0 then return require("minisnip.extras").rep(n) end
    seen[n] = true
    return node.i(n, nodes and flatten(nodes) or "")
  end

  local function seq(stop)
    local nodes, buf = {}, {}
    local function flush()
      if #buf > 0 then nodes[#nodes + 1] = node.t(table.concat(buf)); buf = {} end
    end
    local function push(n) flush(); nodes[#nodes + 1] = n end
    while pos <= #body do
      local ch = body:sub(pos, pos)
      if ch == "\\" and body:sub(pos + 1, pos + 1):match("[%$}\\,|]") then
        buf[#buf + 1] = body:sub(pos + 1, pos + 1)
        pos = pos + 2
      elseif stop and ch == stop then
        break
      elseif ch == "$" then
        local num = body:match("^%$(%d+)", pos)
        local bnum, kind = body:match("^%${(%d+)([:|}])", pos)
        local name = body:match("^%$([%a_][%w_]*)", pos)
        local bname, bkind = body:match("^%${([%a_][%w_]*)([:}])", pos)
        if num then
          pos = pos + 1 + #num
          push(tabstop(tonumber(num)))
        elseif bnum and kind == "}" then
          pos = pos + 3 + #bnum
          push(tabstop(tonumber(bnum)))
        elseif bnum and kind == ":" then
          pos = pos + 3 + #bnum
          local inner = seq("}")
          pos = pos + 1
          push(tabstop(tonumber(bnum), inner))
        elseif bnum and kind == "|" then
          pos = pos + 3 + #bnum
          local choices, cur = {}, {}
          while pos <= #body and body:sub(pos, pos + 1) ~= "|}" do
            local c = body:sub(pos, pos)
            if c == "\\" then cur[#cur + 1] = body:sub(pos + 1, pos + 1); pos = pos + 2
            elseif c == "," then choices[#choices + 1] = node.t(table.concat(cur)); cur = {}; pos = pos + 1
            else cur[#cur + 1] = c; pos = pos + 1 end
          end
          choices[#choices + 1] = node.t(table.concat(cur))
          pos = pos + 2
          seen[tonumber(bnum)] = true
          push(node.c(tonumber(bnum), choices))
        elseif name or bname then
          local default = ""
          if name then
            pos = pos + 1 + #name
          else
            name = bname
            pos = pos + 3 + #bname
            if bkind == ":" then default = flatten(seq("}")); pos = pos + 1 end
          end
          local var = name
          push(node.f(function(_, parent)
            local v = parent.snippet.env[var]
            if v == nil or v == "" or (type(v) == "table" and #v == 0) then return default end
            return v
          end))
        else
          buf[#buf + 1] = ch
          pos = pos + 1
        end
      else
        buf[#buf + 1] = ch
        pos = pos + 1
      end
    end
    flush()
    return nodes
  end

  return seq(nil)
end

function M.parse_snippet(context, body)
  return require("minisnip").snippet(context, M.parse(body))
end

return M
