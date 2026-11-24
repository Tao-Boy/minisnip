if vim.g.loaded_luasnip then return end
vim.g.loaded_luasnip = true

local function plug(name, fn)
  vim.keymap.set({ "i", "s", "n" }, "<Plug>luasnip-" .. name, function() fn(require("luasnip")) end, { silent = true })
end
plug("expand-or-jump", function(ls) ls.expand_or_jump() end)
plug("expand-snippet", function(ls) ls.expand() end)
plug("jump-next", function(ls) ls.jump(1) end)
plug("jump-prev", function(ls) ls.jump(-1) end)
plug("next-choice", function(ls) ls.change_choice(1) end)
plug("prev-choice", function(ls) ls.change_choice(-1) end)
