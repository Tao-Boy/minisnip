-- luasnip.loaders: edit_snippet_files
local M = {}

-- pick one of the snippet files for the current filetypes and edit it
function M.edit_snippet_files()
  local files = require("luasnip.loaders.from_lua").files
  local fts = {}
  for k, ft in ipairs(require("luasnip").get_snippet_filetypes()) do fts[ft] = k end
  local items = {}
  for path, ft in pairs(files) do
    if fts[ft] then items[#items + 1] = { path = path, ft = ft } end
  end
  table.sort(items, function(a, b)
    if fts[a.ft] ~= fts[b.ft] then return fts[a.ft] < fts[b.ft] end
    return a.path < b.path
  end)
  if #items == 0 then return vim.notify("luasnip: no snippet files for this filetype") end
  vim.ui.select(items, {
    prompt = "Snippet file",
    format_item = function(it) return it.ft .. ": " .. vim.fn.fnamemodify(it.path, ":~") end,
  }, function(it)
    if it then vim.cmd.edit(vim.fn.fnameescape(it.path)) end
  end)
end

return M
