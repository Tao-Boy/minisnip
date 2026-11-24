-- minisnip: a minimal LuaSnip-compatible snippet engine.
local node = require("minisnip.node")
local api = vim.api
local unpack = unpack or table.unpack

local M = {}

M.text_node, M.t = node.t, node.t
M.insert_node, M.i = node.i, node.i
M.function_node, M.f = node.f, node.f
M.dynamic_node, M.d = node.d, node.d
M.snippet_node, M.sn = node.sn, node.sn
M.choice_node, M.c = node.c, node.c
M.restore_node, M.r = node.r, node.r

function M.snippet(context, nodes, opts)
  if type(context) == "string" then context = { trig = context } end
  opts = opts or {}
  local trig = context.trig or ""
  local reg = context.regTrig or context.trigEngine == "pattern"
  local dscr = context.dscr or context.desc
  return {
    trigger = trig,
    regTrig = reg or nil,
    wordTrig = context.wordTrig ~= false,
    priority = context.priority,
    snippetType = context.snippetType,
    condition = context.condition or opts.condition,
    show_condition = context.show_condition or opts.show_condition,
    name = context.name or trig,
    dscr = type(dscr) == "string" and vim.split(dscr, "\n", { plain = true }) or dscr,
    hidden = context.hidden,
    nodes = node.wrap(nodes),
    last_byte = not reg and trig:byte(-1) or nil,
  }
end
M.s = M.snippet

M.parser = {
  parse_snippet = function(context, body) return require("minisnip.parser").parse_snippet(context, body) end,
}

------------------------------------------------------------------ registry
local R = { by_ft = {}, extends = {}, cache = {}, by_id = {}, n = 0 }

function M.add_snippets(ft, snippets, opts)
  opts = opts or {}
  if ft == nil then
    for k, v in pairs(snippets) do M.add_snippets(k, v, opts) end
    return
  end
  local list = R.by_ft[ft] or {}
  R.by_ft[ft] = list
  for _, snip in ipairs(snippets) do
    R.n = R.n + 1
    snip.id, snip.order, snip.key = R.n, R.n, opts.key
    snip.priority = snip.priority or opts.default_priority or 1000
    snip.ftype = snip.snippetType == "autosnippet" and "autosnippets"
      or snip.snippetType == "snippet" and "snippets"
      or opts.type or "snippets"
    R.by_id[R.n] = snip
    list[#list + 1] = snip
  end
  R.cache = {}
  pcall(api.nvim_exec_autocmds, "User", { pattern = "LuasnipSnippetsAdded", modeline = false })
end

-- remove all snippets that were added with `key` (used when reloading a file)
function M.clean_key(key)
  for ft, list in pairs(R.by_ft) do
    R.by_ft[ft] = vim.tbl_filter(function(s) return s.key ~= key end, list)
  end
  R.cache = {}
end

function M.filetype_extend(ft, extend)
  local l = R.extends[ft] or {}
  R.extends[ft] = l
  for _, e in ipairs(extend) do
    if not vim.tbl_contains(l, e) then l[#l + 1] = e end
  end
  R.cache = {}
end

function M.get_snippet_filetypes()
  local res, seen = {}, {}
  local function add(ft)
    if seen[ft] then return end
    seen[ft], res[#res + 1] = true, ft
    for _, e in ipairs(R.extends[ft] or {}) do add(e) end
  end
  for _, ft in ipairs(vim.split(vim.bo.filetype, ".", { plain = true })) do
    if ft ~= "" then add(ft) end
  end
  add("all")
  return res
end

function M.get_snippets(ft, opts)
  local ty = opts and opts.type or "snippets"
  if ft == nil then
    local res = {}
    for k in pairs(R.by_ft) do res[k] = M.get_snippets(k, opts) end
    return res
  end
  return vim.tbl_filter(function(s) return s.ftype == ty end, R.by_ft[ft] or {})
end

function M.get_id_snippet(id) return R.by_id[id] end

-- candidates for the current buffer: priority desc, then filetype order, then definition order
local function candidates(ty)
  local fts = M.get_snippet_filetypes()
  local key = ty .. "|" .. table.concat(fts, ",")
  if R.cache[key] then return R.cache[key] end
  local list, rank = {}, {}
  for k, ft in ipairs(fts) do
    for _, s in ipairs(R.by_ft[ft] or {}) do
      if s.ftype == ty then
        list[#list + 1] = s
        rank[s] = rank[s] or k
      end
    end
  end
  table.sort(list, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if rank[a] ~= rank[b] then return rank[a] < rank[b] end
    return a.order < b.order
  end)
  R.cache[key] = list
  return list
end

-- LuaSnip semantics: trigger must end at the cursor; wordTrig forbids [%w_] before it.
local function match(snip, line)
  local m, caps
  if snip.regTrig then
    local res = { line:find(snip.trigger .. "$") }
    if not res[1] then return end
    m, caps = line:sub(res[1]), { unpack(res, 3) }
  else
    if line:byte(-1) ~= snip.last_byte or line:sub(-#snip.trigger) ~= snip.trigger then return end
    m, caps = snip.trigger, {}
  end
  local from = #line - #m + 1
  if snip.wordTrig and from > 1 and line:sub(from - 1, from - 1):match("[%w_]") then return end
  if snip.condition and not snip.condition(line, m, caps) then return end
  return m, caps
end

local function line_to_cursor()
  return api.nvim_get_current_line():sub(1, api.nvim_win_get_cursor(0)[2])
end

local function find(ty)
  local line = line_to_cursor()
  for _, snip in ipairs(candidates(ty)) do
    local m, caps = match(snip, line)
    if m then return snip, m, caps end
  end
end

------------------------------------------------------------------- session
-- S.cur is the innermost active snippet instance; nested snippets point to
-- the insert node containing them through `parent_node`.
local S = { cur = nil, buf = nil }

local function current()
  if S.cur and S.buf == api.nvim_get_current_buf() and api.nvim_buf_is_valid(S.buf) then return S.cur end
end

local function root_of(snip)
  while snip.parent_node do snip = node.snippet_of(snip.parent_node) end
  return snip
end

local function exit_snippet(snip)
  node.del_marks(snip)
  local p = snip.parent_node
  if p then
    p.child = nil
    S.cur = node.snippet_of(p)
    S.cur.focus = p
    node.focus(p)
  else
    S.cur = nil
  end
end

local function exit_all()
  if S.cur then
    local ok = pcall(node.del_marks, root_of(S.cur))
    if not ok then pcall(api.nvim_buf_clear_namespace, S.buf, node.ns, 0, -1) end
  end
  S.cur = nil
end
M.unlink_current = exit_all

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "ni", false)
end

function M._insert_at(row, col)
  api.nvim_win_set_cursor(0, { row + 1, col })
  if col >= #api.nvim_get_current_line() then vim.cmd("startinsert!") else vim.cmd("startinsert") end
end

local function cursor_to(row, col)
  if api.nvim_get_mode().mode:sub(1, 1) == "i" then
    api.nvim_win_set_cursor(0, { row + 1, col })
  else
    feed(("<Esc><Cmd>lua require('minisnip')._insert_at(%d,%d)<CR>"):format(row, col))
  end
end

local function select_range(sr, sc, er, ec)
  if ec == 0 then
    er = er - 1
    ec = #api.nvim_buf_get_lines(0, er, er + 1, true)[1]
  end
  local endcol = ec + 1 -- 1-based, exclusive
  if vim.o.selection ~= "exclusive" then
    local line = api.nvim_buf_get_lines(0, er, er + 1, true)[1]
    endcol = ec + vim.str_utf_start(line, ec) -- 1-based start of last char
  end
  feed(("<Esc><Cmd>call cursor(%d,%d)<CR>v<Cmd>call cursor(%d,%d)<CR><C-g>"):format(sr + 1, sc + 1, er + 1, endcol))
end

local function enter(leaf)
  local snip = node.snippet_of(leaf)
  S.cur, snip.focus = snip, leaf
  node.focus(leaf)
  local sr, sc, er, ec = node.range(leaf)
  if leaf.type == "i" and leaf.pos ~= 0 and (sr ~= er or sc ~= ec) then
    select_range(sr, sc, er, ec)
  elseif leaf.type == "i" and leaf.pos ~= 0 then
    cursor_to(sr, sc)
  else
    cursor_to(er, ec)
  end
end

local function inside(n, pos)
  local sr, sc, er, ec = node.range(n)
  return (pos[1] > sr or pos[1] == sr and pos[2] >= sc) and (pos[1] < er or pos[1] == er and pos[2] <= ec)
end

local function make_env(trigger, captures)
  local raw, dedent = require("minisnip.select").retrieve()
  local env = {
    SELECT_RAW = raw, LS_SELECT_RAW = raw, TM_SELECTED_TEXT = raw,
    SELECT_DEDENT = dedent, LS_SELECT_DEDENT = dedent, LS_TRIGGER = trigger,
  }
  for k, c in ipairs(captures) do env["LS_CAPTURE_" .. k] = c end
  return setmetatable(env, { __index = function(_, k) return require("minisnip.parser").var(k) end })
end

--- Expand `snip` at the cursor.
--- opts: trigger (text to remove before the cursor), captures,
---       clear_region = { from = {row, col}, to = {row, col} } (0-based).
function M.snip_expand(snip, opts)
  opts = opts or {}
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local trigger, captures = opts.trigger or "", opts.captures or {}
  local from = opts.clear_region and opts.clear_region.from or { row, col - #trigger }
  local to = opts.clear_region and opts.clear_region.to or { row, col }

  -- nest into the focused insert node if the trigger was typed inside it
  if S.cur and S.buf ~= buf then exit_all() end
  local parent
  while S.cur do
    local f = S.cur.focus
    local ok, ins = pcall(function() return f.type == "i" and f.pos ~= 0 and inside(f, from) and inside(f, to) end)
    if not ok then exit_all() break end
    if ins then parent = f break end
    exit_snippet(S.cur)
  end

  local line = api.nvim_buf_get_lines(buf, from[1], from[1] + 1, true)[1]
  local inst = node.new_snippet(snip, buf, make_env(trigger, captures), captures, trigger)
  inst.indent = line:sub(1, from[2]):match("^%s*")
  local b = node.builder(from[1], from[2], inst.indent)
  node.render(inst, b)
  api.nvim_buf_set_text(buf, from[1], from[2], to[1], to[2], b.lines)
  node.place_marks(inst)

  local leaf = node.first_in(inst, 1)
  if leaf.type == "i" and leaf.pos == 0 then
    -- nothing to jump to: place the cursor at $0 and forget the snippet
    local _, _, er, ec = node.range(leaf)
    node.del_marks(inst)
    cursor_to(er, ec)
    return true
  end
  inst.parent_node = parent
  if parent then parent.child = inst end
  S.cur, S.buf = inst, buf
  enter(leaf)
  return true
end

function M.expand_auto()
  local snip, m, caps = find("autosnippets")
  if snip then M.snip_expand(snip, { trigger = m, captures = caps }) end
end

function M.expand()
  local snip, m, caps = find("snippets")
  if not snip then return false end
  return M.snip_expand(snip, { trigger = m, captures = caps })
end

function M.expandable() return find("snippets") ~= nil end

function M.lsp_expand(body)
  return M.snip_expand(require("minisnip.parser").parse_snippet("", body), {})
end

---------------------------------------------------------------------- jumps
function M.jumpable(dir)
  local cur = current()
  return cur ~= nil and node.next_leaf(cur.focus, dir or 1) ~= nil
end

function M.jump(dir)
  local cur = current()
  if not cur then return false end
  local leaf, exits = node.next_leaf(cur.focus, dir)
  if not leaf then return false end
  for _, s in ipairs(exits) do exit_snippet(s) end
  enter(leaf)
  return true
end

function M.in_snippet()
  local cur = current()
  if not cur then return false end
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local ok, res = pcall(inside, root_of(cur), { row - 1, col })
  return ok and res
end

function M.locally_jumpable(dir) return M.jumpable(dir) and M.in_snippet() end
function M.expand_or_jumpable() return M.expandable() or M.jumpable(1) end
function M.expand_or_locally_jumpable() return M.expandable() or M.locally_jumpable(1) end
function M.expand_or_jump() return M.expand() or M.jump(1) end

-------------------------------------------------------------------- choices
local function active_choice()
  local cur = current()
  local n = cur and cur.focus
  while n do
    if n.type == "c" then return n end
    n = node.up(n)
  end
end

function M.choice_active() return active_choice() ~= nil end

function M.set_choice(idx)
  local c = active_choice()
  if not c then return false end
  local owner = node.snippet_of(c)
  while S.cur and S.cur ~= owner do exit_snippet(S.cur) end
  -- restore_cursor: remember which insert node (by order) held the cursor, and where
  local keep
  if c.opts.restore_cursor and S.cur.focus.type == "i" then
    local k, nth = 0, nil
    node.walk(c.active, function(n)
      if n.type == "i" then k = k + 1; if n == S.cur.focus then nth = k end end
    end)
    local sr, sc = node.range(S.cur.focus)
    local row, col = unpack(api.nvim_win_get_cursor(0))
    if nth then keep = { nth = nth, drow = row - 1 - sr, col = row - 1 == sr and col - sc or col } end
  end
  node.save_restore(c.active)
  node.del_marks(c.active)
  c.idx = (idx - 1) % #c.choices + 1
  c.active = node.instantiate(c.choices[c.idx], c, c.root)
  if c.active.type == "d" then node.gen_dynamic(c.active) end
  node.rerender(c)
  if keep then
    local k, leaf = 0, nil
    node.walk(c.active, function(n)
      if n.type == "i" then k = k + 1; if k == keep.nth then leaf = n end end
    end)
    if leaf then
      S.cur.focus = leaf
      node.focus(leaf)
      local sr, sc, er, ec = node.range(leaf)
      local row = math.min(sr + keep.drow, er)
      local col = row == sr and sc + keep.col or keep.col
      if row == er then col = math.min(col, ec) end
      cursor_to(row, col)
      return true
    end
  end
  enter(node.first_in(c.active, 1) or c)
  return true
end

function M.change_choice(dir)
  local c = active_choice()
  return c ~= nil and M.set_choice(c.idx + dir)
end

---------------------------------------------------- function/dynamic updates
local function update()
  local cur = current()
  if not cur then return end
  local todo = {}
  node.walk(root_of(cur), function(n)
    if n.type == "f" or n.type == "d" and #n.args > 0 then todo[#todo + 1] = n end
  end)
  local changed = false
  for _, n in ipairs(todo) do
    if n.mark then
      if n.type == "f" then
        local v = node.to_lines(n.fn(node.args_of(n), n.parent, unpack(n.user_args)))
        if not vim.deep_equal(v, n.value) then node.rerender(n); changed = true end
      elseif not vim.deep_equal(node.args_of(n), n.last_args) then
        local f, was_inside = S.cur.focus, false
        while f do was_inside = was_inside or f == n; f = node.up(f) end
        if was_inside then
          while S.cur ~= node.snippet_of(n) do exit_snippet(S.cur) end
        end
        node.del_marks(n.snip)
        node.gen_dynamic(n)
        node.rerender(n)
        changed = true
        if was_inside then
          local leaf = node.first_in(n.snip, 1)
          if leaf then enter(leaf) else S.cur.focus = n end
        end
      end
    end
  end
  if changed and S.cur then node.focus(S.cur.focus) end
end

function M.active_update_dependents()
  local ok, err = pcall(update)
  if not ok then
    exit_all()
    vim.notify("minisnip: snippet state lost (" .. tostring(err) .. ")", vim.log.levels.DEBUG)
  end
end

--------------------------------------------------------------------- config
local config = { enable_autosnippets = false, update_events = { "InsertLeave" } }

function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  if opts.store_selection_keys then
    opts.cut_selection_keys, opts.store_selection_keys = opts.store_selection_keys, nil
  end
  config = vim.tbl_extend("force", config, opts)

  local group = api.nvim_create_augroup("minisnip", { clear = true })
  if config.enable_autosnippets then
    local typed = false
    api.nvim_create_autocmd("InsertCharPre", { group = group, callback = function() typed = true end })
    api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
      group = group,
      callback = function()
        if typed then
          typed = false
          M.expand_auto() -- looked up on M so user overrides of expand_auto apply
        end
      end,
    })
  end
  local ev = config.update_events
  api.nvim_create_autocmd(type(ev) == "string" and { ev } or ev, {
    group = group,
    callback = function() M.active_update_dependents() end,
  })
  if config.cut_selection_keys then
    vim.keymap.set("x", config.cut_selection_keys, require("minisnip.select").cut_keys, { silent = true })
  end
end
M.set_config = M.setup
M.config = { setup = M.setup, set_config = M.setup }

-- textual preview of a snippet (used for completion documentation)
function M.get_docstring(snip)
  local out = {}
  local function walk(nodes)
    for _, n in ipairs(nodes) do
      if n.type == "t" then out[#out + 1] = table.concat(n.text, "\n")
      elseif n.type == "i" then
        local txt = table.concat(n.text, "\n")
        out[#out + 1] = txt == "" and ("$" .. (n.pos or "")) or ("${" .. (n.pos or "") .. ":" .. txt .. "}")
      elseif n.type == "sn" then walk(n.nodes)
      elseif n.type == "c" then walk({ n.choices[1] })
      elseif n.type == "r" then walk({ n.node })
      else out[#out + 1] = "…" end
    end
  end
  walk(snip.nodes)
  return table.concat(out)
end

M.setup()

return M
