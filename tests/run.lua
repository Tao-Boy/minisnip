-- Headless tests:  nvim --headless -u NONE -l tests/run.lua   (or: -c "luafile tests/run.lua")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.cmd("runtime plugin/minisnip.lua")

local ls = require("luasnip")
local s, sn, t, i, f, d, c, r = ls.s, ls.sn, ls.t, ls.i, ls.f, ls.d, ls.c, ls.r
local fmta = require("luasnip.extras.fmt").fmta
local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep
local l = require("luasnip.extras").lambda
local line_begin = require("luasnip.extras.expand_conditions").line_begin

ls.config.set_config({
  enable_autosnippets = true,
  store_selection_keys = "`",
  update_events = { "TextChanged", "TextChangedI" },
})

local get_visual = function(_, parent)
  if #parent.snippet.env.SELECT_RAW > 0 then
    return sn(nil, t(parent.snippet.env.SELECT_RAW))
  end
  return sn(nil, i(1))
end

local A = { snippetType = "autosnippet" }
local function auto(tbl) return vim.tbl_extend("force", A, tbl) end

ls.add_snippets("tex", {
  s(auto({ trig = "ff" }), fmta("\\frac{<>}{<>}", { i(1), i(2) })),
  s(auto({ trig = "ii" }), fmta("\\(<>\\)", { i(1) })),
  s(auto({ trig = "beg", condition = line_begin }), fmta([[
    \begin{<>}
      <>
    \end{<>}
  ]], { i(1), i(2), rep(1) })),
  s(auto({ trig = "([%a])(%d)", regTrig = true, wordTrig = false }), fmta("<>_<>", {
    f(function(_, snip) return snip.captures[1] end),
    f(function(_, snip) return snip.captures[2] end),
  })),
  s(auto({ trig = "tt" }), fmta("\\text{<>}", { d(1, get_visual) })),
  s(auto({ trig = "cho" }), { c(1, { t("exercise"), t("theorem") }), t(":"), i(2) }),
  s(auto({ trig = "lr" }), {
    c(1, {
      sn(nil, { t("("), r(1, "body", i(1)), t(")") }),
      sn(nil, { t("\\left("), r(1, "body", i(1)), t("\\right)") }),
    }, { restore_cursor = true }),
  }),
  s(auto({ trig = "SES" }), t("short exact sequence")),
  s(auto({ trig = "sq", priority = 2000 }), fmta("\\sqrt{<>}", { i(1, "x") })),
  s({ trig = "note" }, fmt("note {} {}", { i(1), i(2) })),
})
ls.filetype_extend("tex", { "tex_shared" })
ls.add_snippets("tex_shared", { s(auto({ trig = "shd" }), t("shared")) })
ls.add_snippets("lua", {
  s({ trig = "req" }, fmt([[local {} = require("{}")]], { l(l._1:match("[^.]*$"):gsub("[^%a]+", "_"), 1), i(1) })),
  ls.parser.parse_snippet("lm", "local M = {}\n\n$1 \n\nreturn M"),
  ls.parser.parse_snippet("fn", "f(${1:x}, $2) \\$ ${1}$0"),
})

---------------------------------------------------------------- harness
-- Keys go through nvim_input so they are processed like real typing
-- (InsertCharPre/TextChangedI fire); the test coroutine resumes once nvim is idle.
local failures, count = 0, 0
local co
local function wait()
  vim.defer_fn(function() assert(coroutine.resume(co)) end, 5)
  coroutine.yield()
end
local function feed(keys)
  vim.api.nvim_input(keys)
  wait()
end
local function type_(str)
  for ch in str:gmatch(".") do feed(ch == "<" and "<lt>" or ch) end
end
local function buf() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") end
local function check(name, got, want)
  count = count + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s\n  want: %q\n  got:  %q"):format(name, want, got))
  else
    print("ok   " .. name)
  end
end
local function reset(ft)
  ls.unlink_current()
  feed("<Esc>")
  vim.cmd("enew!")
  wait()
  vim.bo.filetype = ft or "tex"
  vim.bo.expandtab, vim.bo.shiftwidth = true, 2
  feed("i")
end
local function jump(dir) feed(dir > 0 and "<Plug>luasnip-jump-next" or "<Plug>luasnip-jump-prev") end
local function cursor() local p = vim.api.nvim_win_get_cursor(0); return p[1] .. ":" .. p[2] end

-------------------------------------------------------------------- tests
local function tests()
reset(); type_("ff"); type_("a"); jump(1); type_("b"); jump(1); type_("!")
check("frac + jumps", buf(), "\\frac{a}{b}!")

reset(); type_("ii"); type_("ff"); type_("1"); jump(1); type_("2"); jump(1); type_("+x"); jump(1); type_(" y")
check("nested snippets", buf(), "\\(\\frac{1}{2}+x\\) y")

reset(); type_("beg"); type_("align"); jump(1); type_("x")
check("rep + dedent + indent", buf(), "\\begin{align}\n  x\n\\end{align}")

reset(); type_("  beg"); type_("eq")
check("indent of current line", buf(), "  \\begin{eq}\n    \n  \\end{eq}")

reset(); type_("a beg")
check("line_begin condition", buf(), "a beg")

reset(); type_("x2")
check("regTrig captures", buf(), "x_2")

reset(); type_("SES.")
check("text-only snippet", buf(), "short exact sequence.")

reset(); type_("tt"); type_("hi"); jump(1); type_(".")
check("dynamic node without selection", buf(), "\\text{hi}.")

reset(); type_("word")
feed("<Esc>v0`")
type_("tt")
check("store_selection_keys + SELECT_RAW", buf(), "\\text{word}")

reset(); type_("cho"); feed("<Plug>luasnip-next-choice"); jump(1); type_("T")
check("choice node", buf(), "theorem:T")

reset(); type_("lr"); type_("abc"); feed("<Plug>luasnip-next-choice"); type_("d")
check("restore node keeps text across choices", buf(), "\\left(abcd\\right)")

reset(); type_("sq"); type_("y"); jump(1); type_("!")
check("select-mode placeholder replaced", buf(), "\\sqrt{y}!")

reset(); type_("ff"); type_("a"); jump(1); jump(-1); type_("Z")
check("jump back selects text", buf(), "\\frac{Z}{}")

reset(); type_("shd")
check("filetype_extend", buf(), "shared")

reset(); type_("note"); check("manual snippet not auto-expanded", buf(), "note")
check("expandable()", tostring(ls.expandable()), "true")
ls.expand(); wait(); type_("A"); jump(1); type_("B")
check("manual expand", buf(), "note A B")

reset("lua"); type_("req"); ls.expand(); wait(); type_("foo.bar-baz")
check("lambda", buf(), 'local bar_baz = require("foo.bar-baz")')

reset("lua"); type_("lm"); ls.expand(); wait(); type_("x")
check("parse_snippet", buf(), "local M = {}\n\nx \n\nreturn M")

reset("lua"); type_("fn"); ls.expand(); wait(); type_("a"); jump(1); type_("b"); jump(1); type_(";")
check("parse_snippet placeholder/mirror/escape", buf(), "f(a, b) $ a;")

reset(); type_("ff"); jump(1); jump(1)
check("not jumpable at end", tostring(ls.jumpable(1)), "false")
check("cursor at $0", cursor(), "1:9")

print(("\n%d/%d passed"):format(count - failures, count))
if failures > 0 then vim.cmd("cquit 1") else vim.cmd("qa!") end
end

co = coroutine.create(function()
  local ok, err = xpcall(tests, debug.traceback)
  if not ok then print(err); vim.cmd("cquit 2") end
end)
vim.schedule(function() assert(coroutine.resume(co)) end)
