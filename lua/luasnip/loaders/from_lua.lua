-- luasnip.loaders.from_lua: load <path>/<ft>.lua and <path>/<ft>/**/*.lua.
-- Each file returns `snippets[, autosnippets]`; files are reloaded on :write.
local M = {}
local files = {} -- normalized path -> filetype
M.files = files

local function snippet_env()
  local ls = require("luasnip")
  local ex = require("luasnip.extras")
  local fmt = require("luasnip.extras.fmt")
  return {
    ls = ls, s = ls.s, sn = ls.sn, t = ls.t, i = ls.i, f = ls.f, d = ls.d, c = ls.c, r = ls.r,
    fmt = fmt.fmt, fmta = fmt.fmta, rep = ex.rep, l = ex.lambda,
    conds = require("luasnip.extras.expand_conditions"),
    parse = ls.parser.parse_snippet,
  }
end

local function load_file(path, ft)
  local ls = require("luasnip")
  ls.clean_key(path)
  local chunk, err = loadfile(path)
  if not chunk then
    return vim.notify("luasnip: " .. err, vim.log.levels.ERROR)
  end
  setfenv(chunk, setmetatable(snippet_env(), { __index = _G }))
  local ok, snips, autos = pcall(chunk)
  if not ok then
    return vim.notify("luasnip: error in " .. path .. ": " .. tostring(snips), vim.log.levels.ERROR)
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
    group = vim.api.nvim_create_augroup("luasnip_loader", { clear = true }),
    pattern = "*.lua",
    callback = function(ev)
      local p = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
      if files[p] then load_file(p, files[p]) end
    end,
  })
end
M.lazy_load = M.load

return M
