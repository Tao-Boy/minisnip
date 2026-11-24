-- store_selection_keys: cut the visual selection so snippets can use SELECT_RAW
local M = {}

M.cut_keys = [[<Esc><Cmd>lua require("minisnip.select").pre()<CR>gv"zs<Cmd>lua require("minisnip.select").post()<CR>]]

local REGS = { '"', "1", "2", "3", "4", "5", "6", "7", "8", "9", "z" }
local saved

function M.pre()
  saved = {}
  for _, r in ipairs(REGS) do saved[r] = { vim.fn.getreg(r), vim.fn.getregtype(r) } end
end

function M.post()
  local raw = vim.split((vim.fn.getreg("z"):gsub("\n$", "")), "\n", { plain = true })
  for r, v in pairs(saved or {}) do vim.fn.setreg(r, v[1], v[2]) end
  local indent
  for _, l in ipairs(raw) do
    local ind = l:match("^(%s*)%S")
    if ind and (not indent or #ind < #indent) then indent = ind end
  end
  local dedent = vim.tbl_map(function(l)
    return indent and l:sub(1, #indent) == indent and l:sub(#indent + 1) or l
  end, raw)
  vim.b.minisnip_select = { raw = raw, dedent = dedent }
end

function M.retrieve()
  local s = vim.b.minisnip_select
  if not s then return {}, {} end
  vim.b.minisnip_select = nil
  return s.raw, s.dedent
end

return M
