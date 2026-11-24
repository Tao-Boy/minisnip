-- Load snippets from lua files: <path>/<ft>.lua and <path>/<ft>/**/*.lua.
-- Each file returns `snippets[, autosnippets]`; files are reloaded on :write.
local M = {}
local files = {} -- normalized path -> filetype

local function snippet_env()
  local ls = require("minisnip")
  local ex = require("minisnip.extras")
  local fmt = require("minisnip.fmt")
  return {
    ls = ls, s = ls.s, sn = ls.sn, t = ls.t, i = ls.i, f = ls.f, d = ls.d, c = ls.c, r = ls.r,
    fmt = fmt.fmt, fmta = fmt.fmta, rep = ex.rep, l = ex.lambda, conds = ex.conditions,
    parse = ls.parser.parse_snippet,
  }
end

local function load_file(path, ft)
  local ls = require("minisnip")
  ls.clean_key(path)
  local chunk, err = loadfile(path)
  if not chunk then
    return vim.notify("minisnip: " .. err, vim.log.levels.ERROR)
  end
  setfenv(chunk, setmetatable(snippet_env(), { __index = _G }))
  local ok, snips, autos = pcall(chunk)
  if not ok then
    return vim.notify("minisnip: error in " .. path .. ": " .. tostring(snips), vim.log.levels.ERROR)
  end
  ls.add_snippets(ft, snips or {}, { type = "snippets", key = path })
  ls.add_snippets(ft, autos or {}, { type = "autosnippets", key = path })
end

local function register(path, ft)
  path = vim.fs.normalize(path)
  files[path] = ft
  load_file(path, ft)
end

function M.load(opts)
  opts = opts or {}
  local paths = opts.paths
  if paths == nil then
    paths = vim.api.nvim_get_runtime_file("luasnippets", true)
  elseif type(paths) == "string" then
    paths = { paths }
  end
  for _, root in ipairs(paths) do
    root = vim.fs.normalize(vim.fn.expand(root))
    for name, ty in vim.fs.dir(root) do
      if ty == "file" and name:match("%.lua$") then
        register(root .. "/" .. name, (name:gsub("%.lua$", "")))
      elseif ty == "directory" then
        for sub, sty in vim.fs.dir(root .. "/" .. name, { depth = 20 }) do
          if sty == "file" and sub:match("%.lua$") then register(root .. "/" .. name .. "/" .. sub, name) end
        end
      end
    end
  end
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("minisnip_loader", { clear = true }),
    pattern = "*.lua",
    callback = function(ev)
      local p = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
      if files[p] then load_file(p, files[p]) end
    end,
  })
end
M.lazy_load = M.load

-- pick one of the snippet files for the current filetypes and edit it
function M.edit_snippet_files()
  local fts = {}
  for k, ft in ipairs(require("minisnip").get_snippet_filetypes()) do fts[ft] = k end
  local items = {}
  for path, ft in pairs(files) do
    if fts[ft] then items[#items + 1] = { path = path, ft = ft } end
  end
  table.sort(items, function(a, b)
    if fts[a.ft] ~= fts[b.ft] then return fts[a.ft] < fts[b.ft] end
    return a.path < b.path
  end)
  if #items == 0 then return vim.notify("minisnip: no snippet files for this filetype") end
  vim.ui.select(items, {
    prompt = "Snippet file",
    format_item = function(it) return it.ft .. ": " .. vim.fn.fnamemodify(it.path, ":~") end,
  }, function(it)
    if it then vim.cmd.edit(vim.fn.fnameescape(it.path)) end
  end)
end

return M
