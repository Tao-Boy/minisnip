if vim.g.loaded_minisnip then return end
vim.g.loaded_minisnip = true

local function plug(names, fn)
  for _, name in ipairs(names) do
    vim.keymap.set({ "i", "s", "n" }, "<Plug>" .. name, fn, { silent = true })
  end
end
local ls = function() return require("minisnip") end
plug({ "luasnip-expand-or-jump", "minisnip-expand-or-jump" }, function() ls().expand_or_jump() end)
plug({ "luasnip-expand-snippet", "minisnip-expand" }, function() ls().expand() end)
plug({ "luasnip-jump-next", "minisnip-jump-next" }, function() ls().jump(1) end)
plug({ "luasnip-jump-prev", "minisnip-jump-prev" }, function() ls().jump(-1) end)
plug({ "luasnip-next-choice", "minisnip-next-choice" }, function() ls().change_choice(1) end)
plug({ "luasnip-prev-choice", "minisnip-prev-choice" }, function() ls().change_choice(-1) end)
