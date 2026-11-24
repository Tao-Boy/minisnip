-- Node constructors, instantiation, rendering and extmark bookkeeping.
--
-- A node *definition* is a plain table created by t/i/f/d/sn/c/r.
-- On expansion definitions are copied into *instances*, which form a tree:
--   snippet/sn -> .nodes, d -> .snip, c -> .active, r -> .inner,
--   i -> .child (a nested snippet expanded inside this insert node).
-- Every instance in the buffer owns one range extmark (`.mark`).
local M = {}

local api = vim.api
local unpack = unpack or table.unpack
M.ns = api.nvim_create_namespace("luasnip")

local function lines_of(text)
  if text == nil then return { "" } end
  if type(text) == "string" then return vim.split(text, "\n", { plain = true }) end
  if #text == 0 then return { "" } end
  return vim.deepcopy(text)
end
M.lines_of = lines_of

local function wrap(nodes)
  if nodes == nil then return {} end
  if nodes.type then return { nodes } end
  return nodes
end
M.wrap = wrap

---------------------------------------------------------------- constructors
function M.t(text) return { type = "t", text = lines_of(text) } end
function M.i(pos, text) return { type = "i", pos = pos, text = lines_of(text) } end
function M.f(fn, args, opts)
  if type(args) ~= "table" or args.type then args = { args } end
  return { type = "f", fn = fn, args = args, user_args = opts and opts.user_args or {} }
end
function M.d(pos, fn, args, opts)
  if type(args) ~= "table" or args.type then args = { args } end
  return { type = "d", pos = pos, fn = fn, args = args, user_args = opts and opts.user_args or {} }
end
function M.sn(pos, nodes) return { type = "sn", pos = pos, nodes = wrap(nodes) } end
function M.c(pos, choices, opts) return { type = "c", pos = pos, choices = wrap(choices), opts = opts or {} } end
function M.r(pos, key, node) return { type = "r", pos = pos, key = key, node = node or M.i(1) } end

-------------------------------------------------------------------- traversal
local function children(n)
  if n.type == "snippet" or n.type == "sn" then return n.nodes end
  local ch = n.snip or n.active or n.inner or n.child
  return ch and { ch } or {}
end

-- pre-order walk over an instance tree
function M.walk(n, fn)
  fn(n)
  for _, ch in ipairs(children(n)) do M.walk(ch, fn) end
end

-- structural parent, crossing from a nested snippet into the insert node holding it
function M.up(n) return n.parent or n.parent_node end

function M.snippet_of(n)
  while n.type ~= "snippet" do n = n.parent end
  return n
end

------------------------------------------------------------------ extmarks
function M.range(n)
  local m = api.nvim_buf_get_extmark_by_id(n.buf, M.ns, n.mark, { details = true })
  return m[1], m[2], m[3].end_row, m[3].end_col
end

-- After edits that destroy the snippet's text (undoing the expansion, deleting
-- all lines, pasting over it) its extmarks can point past the buffer's end.
-- Returns false if any mark in the tree is missing or out of bounds.
function M.valid(root)
  local buf = root.buf
  if not api.nvim_buf_is_valid(buf) then return false end
  local last = api.nvim_buf_line_count(buf) - 1
  local ok = true
  M.walk(root, function(n)
    if not ok or not n.mark then return end
    local m = api.nvim_buf_get_extmark_by_id(buf, M.ns, n.mark, { details = true })
    if not m[1] then ok = false; return end
    local sr, sc, er, ec = m[1], m[2], m[3].end_row, m[3].end_col
    if er > last or sr > er or (sr == er and sc > ec) then ok = false; return end
    local ls = api.nvim_buf_get_lines(buf, sr, er + 1, true)
    ok = sc <= #ls[1] and ec <= #ls[#ls]
  end)
  return ok
end

function M.get_text(n)
  local sr, sc, er, ec = M.range(n)
  return api.nvim_buf_get_text(n.buf, sr, sc, er, ec, {})
end

local function set_mark(n, sr, sc, er, ec, g1, g2)
  n.mark = api.nvim_buf_set_extmark(n.buf, M.ns, sr, sc, {
    id = n.mark, end_row = er, end_col = ec, right_gravity = g1, end_right_gravity = g2,
  })
  n.g1, n.g2 = g1, g2
end

function M.del_marks(n)
  M.walk(n, function(x)
    if x.mark then pcall(api.nvim_buf_del_extmark, x.buf, M.ns, x.mark) end
    x.mark = nil
  end)
end

-- Make `target` the node that grows when text is typed at its edges:
-- it and its ancestors expand, nodes before it stick left, nodes after stick right.
function M.focus(target)
  local root, anc = target, { [target] = true }
  local p = M.up(target)
  while p do
    anc[p], root = true, p
    p = M.up(p)
  end
  local ord, i = {}, 0
  M.walk(root, function(n) i = i + 1; ord[n] = i end)
  local t = ord[target]
  M.walk(root, function(n)
    if not n.mark then return end
    local g1, g2
    if anc[n] then g1, g2 = false, true
    elseif ord[n] < t then g1, g2 = false, false
    else g1, g2 = true, true end
    if n.g1 ~= g1 or n.g2 ~= g2 then
      local sr, sc, er, ec = M.range(n)
      set_mark(n, sr, sc, er, ec, g1, g2)
    end
  end)
end

---------------------------------------------------------- argument handling
local function find_by_pos(container, pos)
  for _, ch in ipairs(container.nodes) do
    if ch.pos == pos then return ch end
  end
end

local function find_by_def(root, def)
  local found
  M.walk(root, function(n) if n.def == def then found = found or n end end)
  return found
end

function M.static_text(n)
  if n.mark then return M.get_text(n) end
  local b = { lines = { "" }, row = 0, col = 0, indent = "" }
  M.render(n, b, true)
  return b.lines
end

function M.args_of(n)
  local container = n.parent
  while container.type ~= "snippet" and container.type ~= "sn" do container = container.parent end
  local res = {}
  for k, a in ipairs(n.args) do
    local ref = type(a) == "number" and find_by_pos(container, a)
      or type(a) == "table" and find_by_def(M.snippet_of(n), a)
    res[k] = ref and M.static_text(ref) or { "" }
  end
  return res
end

local function to_lines(v)
  if type(v) == "table" then return #v > 0 and v or { "" } end
  return vim.split(tostring(v or ""), "\n", { plain = true })
end
M.to_lines = to_lines

-------------------------------------------------------------- instantiation
local instantiate

local function gen_dynamic(n)
  local res = n.fn(M.args_of(n), n.parent, n.state, unpack(n.user_args))
  if type(res) ~= "table" then res = M.t(res) end
  if res.type ~= "sn" then res = M.sn(nil, res) end
  n.last_args = M.args_of(n)
  n.snip = instantiate(res, n, n.root)
end
M.gen_dynamic = gen_dynamic

-- restore nodes: remember insert-node contents by key across choice changes
function M.save_restore(n)
  M.walk(n, function(x)
    if x.type == "r" and x.mark then
      local saved = {}
      M.walk(x.inner, function(y) if y.type == "i" and y.mark then saved[#saved + 1] = M.get_text(y) end end)
      x.root.restore[x.key] = saved
    end
  end)
end

function instantiate(def, parent, root)
  local n = setmetatable({}, { __index = def })
  n.def, n.parent, n.root, n.buf = def, parent, root, root.buf
  if def.type == "sn" then
    n.nodes = {}
    n.snippet, n.env, n.captures, n.trigger = root, root.env, root.captures, root.trigger
    for k, ch in ipairs(def.nodes) do n.nodes[k] = instantiate(ch, n, root) end
    for _, ch in ipairs(n.nodes) do if ch.type == "d" then gen_dynamic(ch) end end
  elseif def.type == "i" then
    n.text = vim.deepcopy(def.text)
  elseif def.type == "c" then
    n.idx = 1
    n.active = instantiate(def.choices[1], n, root)
    if n.active.type == "d" then gen_dynamic(n.active) end
  elseif def.type == "r" then
    n.inner = instantiate(def.node, n, root)
    local saved = root.restore[def.key]
    if saved then
      local k = 0
      M.walk(n.inner, function(y)
        if y.type == "i" then k = k + 1; y.text = saved[k] or y.text end
      end)
    end
    if n.inner.type == "d" then gen_dynamic(n.inner) end
  end
  return n
end
M.instantiate = instantiate

-- top-level snippet instance
function M.new_snippet(snip, buf, env, captures, trigger)
  local n = setmetatable({}, { __index = snip })
  n.type, n.def, n.buf, n.restore = "snippet", snip, buf, {}
  n.snippet, n.env, n.captures, n.trigger = n, env, captures, trigger
  n.nodes = {}
  local has_zero = false
  for k, ch in ipairs(snip.nodes) do
    n.nodes[k] = instantiate(ch, n, n)
    if ch.pos == 0 then has_zero = true end
  end
  if not has_zero then n.nodes[#n.nodes + 1] = instantiate(M.i(0), n, n) end
  for _, ch in ipairs(n.nodes) do if ch.type == "d" then gen_dynamic(ch) end end
  return n
end

------------------------------------------------------------------ rendering
local function append(b, lines)
  local tab = vim.bo.expandtab and string.rep(" ", vim.fn.shiftwidth()) or nil
  for k, l in ipairs(lines) do
    if tab then l = l:gsub("\t", tab) end
    if k > 1 then
      b.lines[#b.lines + 1] = b.indent
      b.row, b.col = b.row + 1, #b.indent
    end
    b.lines[#b.lines] = b.lines[#b.lines] .. l
    b.col = b.col + #l
  end
end

-- Render instance `n` into builder `b`, recording absolute positions.
-- With `static`, f-nodes reuse their cached value instead of being evaluated.
function M.render(n, b, static)
  local s = { b.row, b.col }
  local ty = n.type
  if ty == "t" then
    append(b, n.text)
  elseif ty == "i" then
    append(b, n.text)
  elseif ty == "f" then
    if not static or not n.value then n.value = to_lines(n.fn(M.args_of(n), n.parent, unpack(n.user_args))) end
    append(b, n.value)
  elseif ty == "snippet" or ty == "sn" then
    for _, ch in ipairs(n.nodes) do M.render(ch, b, static) end
  else
    M.render(n.snip or n.active or n.inner, b, static)
  end
  if not static then n.s, n.e = s, { b.row, b.col } end
end

-- after a render into the buffer, (re)create marks for the whole subtree
function M.place_marks(n)
  M.walk(n, function(x)
    if x.s then
      set_mark(x, x.s[1], x.s[2], x.e[1], x.e[2], true, true)
      x.g1, x.s, x.e = nil, nil, nil -- force focus() to recompute gravity
    end
  end)
end

-- Builder starting at an absolute buffer position.
function M.builder(row, col, indent)
  return { lines = { "" }, row = row, col = col, indent = indent }
end

-- Re-render instance `n` in place (after its content changed). With `join`, the
-- change is merged into the previous undo step (dependents follow their source).
function M.rerender(n, join)
  M.focus(n)
  local sr, sc, er, ec = M.range(n)
  for _, ch in ipairs(children(n)) do M.del_marks(ch) end
  if n.type == "f" then n.value = nil end
  local b = M.builder(sr, sc, n.root.indent)
  M.render(n, b)
  if join then pcall(vim.cmd.undojoin) end
  api.nvim_buf_set_text(n.buf, sr, sc, er, ec, b.lines)
  M.place_marks(n)
end

------------------------------------------------------------- jump structure
local JUMPABLE = { i = true, sn = true, d = true, c = true, r = true }

local function stops(container)
  local l = {}
  for _, ch in ipairs(container.nodes) do
    if ch.pos and JUMPABLE[ch.type] then l[#l + 1] = ch end
  end
  table.sort(l, function(a, b)
    return (a.pos == 0 and math.huge or a.pos) < (b.pos == 0 and math.huge or b.pos)
  end)
  return l
end

local first_leaf

-- first jump target inside an arbitrary node (used for containers and choice items)
local function first_in(n, dir)
  if n.type == "sn" or n.type == "snippet" then
    local l = stops(n)
    local a, z = 1, #l
    if dir < 0 then a, z = #l, 1 end
    for k = a, z, dir do
      local leaf = first_leaf(l[k], dir)
      if leaf then return leaf end
    end
  elseif n.type ~= "t" and n.type ~= "f" then
    return first_leaf(n, dir)
  end
end
M.first_in = first_in

function first_leaf(n, dir)
  if n.type == "i" then return n end
  if n.type == "c" then return first_in(n.active, dir) or n end
  return first_in(n.snip or n.inner or n, dir)
end

-- Next jump target from leaf `n`. Returns target and the list of nested
-- snippets that are left on the way (innermost first).
function M.next_leaf(n, dir)
  local exits = {}
  -- the root snippet itself is the position before its first node (like LuaSnip)
  if n.type == "snippet" then return dir > 0 and first_in(n, 1) or nil, exits end
  while true do
    local p = n.parent
    if p.type == "sn" or p.type == "snippet" then
      local l = stops(p)
      local k
      for idx, x in ipairs(l) do if x == n then k = idx end end
      if k then
        for j = k + dir, dir > 0 and #l or 1, dir do
          local leaf = first_leaf(l[j], dir)
          if leaf then return leaf, exits end
        end
      end
      if p.type == "snippet" then
        if not p.parent_node then return dir < 0 and p or nil, exits end
        exits[#exits + 1] = p
        if dir < 0 then return p.parent_node, exits end
        n = p.parent_node
      else
        n = p
      end
    else
      n = p -- c / d / r wrappers: continue from the wrapper itself
    end
  end
end

return M
