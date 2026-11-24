-- blink.cmp source: sources.providers.snippets = { module = "minisnip.blink" }
local api = vim.api
local unpack = unpack or table.unpack
local KIND = vim.lsp.protocol.CompletionItemKind.Snippet

local source = {}

function source.new(opts)
  return setmetatable({ opts = vim.tbl_extend("keep", opts or {}, { show_autosnippets = false }) }, { __index = source })
end

function source:enabled() return true end

function source:get_completions(_, callback)
  local ls = require("minisnip")
  local line = api.nvim_get_current_line():sub(1, api.nvim_win_get_cursor(0)[2])
  local items = {}
  local types = self.opts.show_autosnippets and { "snippets", "autosnippets" } or { "snippets" }
  for _, ft in ipairs(ls.get_snippet_filetypes()) do
    for _, ty in ipairs(types) do
      for _, snip in ipairs(ls.get_snippets(ft, { type = ty })) do
        if not snip.hidden and (not snip.show_condition or snip.show_condition(line)) then
          items[#items + 1] = {
            label = snip.regTrig and snip.name or snip.trigger,
            kind = KIND,
            insertText = snip.trigger,
            insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
            sortText = ("%08d"):format(100000 - snip.priority) .. snip.trigger,
            data = { minisnip_id = snip.id, ft = ft },
          }
        end
      end
    end
  end
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

function source:resolve(item, callback)
  local ls = require("minisnip")
  local snip = ls.get_id_snippet(item.data.minisnip_id)
  local doc = {}
  if snip.dscr then vim.list_extend(doc, snip.dscr); doc[#doc + 1] = "" end
  doc[#doc + 1] = "```" .. item.data.ft
  vim.list_extend(doc, vim.split(ls.get_docstring(snip), "\n", { plain = true }))
  doc[#doc + 1] = "```"
  item = vim.deepcopy(item)
  item.documentation = { kind = "markdown", value = table.concat(doc, "\n") }
  callback(item)
end

function source:execute(_, item, callback)
  local ls = require("minisnip")
  local snip = ls.get_id_snippet(item.data.minisnip_id)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line():sub(1, col)
  local range = item.textEdit and item.textEdit.range
  local start = range and range.start.character or (line:find("[%w_]*$") - 1)
  local typed = line:sub(start + 1)
  local captures = snip.regTrig and { typed:match(snip.trigger) } or {}
  ls.snip_expand(snip, {
    trigger = typed,
    captures = captures,
    clear_region = { from = { row - 1, start }, to = { row - 1, col } },
  })
  callback()
end

return source
