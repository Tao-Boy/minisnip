-- rep, lambda and condition objects (subset of luasnip.extras / luasnip.extras.conditions)
local node = require("minisnip.node")
local M = {}

function M.rep(idx)
  return node.f(function(args) return args[1] end, { idx })
end

------------------------------------------------------------------- lambda
-- l(l._1:match("x"):gsub(...), 1) builds a function node from a recorded expression.
local Lmt = {}
local function L(fn) return setmetatable({ _fn = fn }, Lmt) end
local function eval(x, a)
  if getmetatable(x) == Lmt then return x._fn(a) end
  return x
end
Lmt.__index = function(self, k)
  return L(function(a) return eval(self, a)[k] end)
end
Lmt.__call = function(self, ...)
  local params = { ... }
  local n = select("#", ...)
  return L(function(a)
    local vals = {}
    for k = 1, n do vals[k] = eval(params[k], a) end
    return (eval(self, a)((unpack or table.unpack)(vals, 1, n)))
  end)
end
Lmt.__concat = function(x, y)
  return L(function(a) return tostring(eval(x, a)) .. tostring(eval(y, a)) end)
end

M.lambda = setmetatable({}, {
  __index = function(_, k)
    local idx = type(k) == "string" and tonumber(k:match("^_(%d+)$"))
    if idx then return L(function(a) return table.concat(a[idx] or {}, "\n") end) end
  end,
  __call = function(_, expr, args)
    return node.f(function(a) return tostring(eval(expr, a)) end, args)
  end,
})
M.l = M.lambda

--------------------------------------------------------------- conditions
local cmt = {}
local function make_condition(func) return setmetatable({ func = func }, cmt) end
cmt.__call = function(self, ...) return self.func(...) end
cmt.__unm = function(a) return make_condition(function(...) return not a(...) end) end
cmt.__add = function(a, b) return make_condition(function(...) return a(...) or b(...) end) end
cmt.__mul = function(a, b) return make_condition(function(...) return a(...) and b(...) end) end
cmt.__sub = function(a, b) return make_condition(function(...) return a(...) and not b(...) end) end
cmt.__pow = function(a, b) return make_condition(function(...) return (a(...) and true or false) ~= (b(...) and true or false) end) end
M.make_condition = make_condition

M.conditions = {
  line_begin = make_condition(function(line, trig)
    return line:sub(1, -(#trig + 1)):match("^%s*$") ~= nil
  end),
  line_end = make_condition(function()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    return col == #vim.api.nvim_get_current_line()
  end),
}

return M
