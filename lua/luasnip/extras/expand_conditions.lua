-- luasnip.extras.expand_conditions: condition objects, combinable with * + - ^ and unary -
local M = {}

local cmt = {}
local function make_condition(func) return setmetatable({ func = func }, cmt) end
cmt.__call = function(self, ...) return self.func(...) end
cmt.__unm = function(a) return make_condition(function(...) return not a(...) end) end
cmt.__add = function(a, b) return make_condition(function(...) return a(...) or b(...) end) end
cmt.__mul = function(a, b) return make_condition(function(...) return a(...) and b(...) end) end
cmt.__sub = function(a, b) return make_condition(function(...) return a(...) and not b(...) end) end
cmt.__pow = function(a, b) return make_condition(function(...) return (a(...) and true or false) ~= (b(...) and true or false) end) end
M.make_condition = make_condition

M.line_begin = make_condition(function(line, trig)
  return line:sub(1, -(#trig + 1)):match("^%s*$") ~= nil
end)

M.line_end = make_condition(function()
  return vim.api.nvim_win_get_cursor(0)[2] == #vim.api.nvim_get_current_line()
end)

return M
