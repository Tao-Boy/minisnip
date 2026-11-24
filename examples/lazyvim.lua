-- Drop-in replacement for nvim/.config/nvim/lua/plugins/default/luasnip.lua
-- Also remove "lazyvim.plugins.extras.coding.luasnip" from lazyvim.json,
-- otherwise LazyVim keeps installing the real LuaSnip.
-- minisnip has no completion-engine integration: snippets expand by trigger
-- (autosnippets) or through require("luasnip").expand().
return {
  {
    "tao-boy/minisnip",
    event = "InsertEnter",
    config = function()
      local ls = require("luasnip") -- compatibility module, same table as require("minisnip")
      ls.config.set_config({
        enable_autosnippets = true,
        store_selection_keys = "`",
        update_events = { "TextChanged", "TextChangedI" },
      })
      ls.filetype_extend("tex", { "tex_shared" })
      ls.filetype_extend("markdown", { "tex_shared" })
      require("luasnip.loaders.from_lua").load({ paths = "~/.config/nvim/LuaSnip" })
      local auto_expand = ls.expand_auto
      ls.expand_auto = function(...)
        vim.o.undolevels = vim.o.undolevels -- undo break before every autosnippet
        auto_expand(...)
      end
    end,
    keys = {
      {
        "fj",
        function()
          -- expand a manual snippet (e.g. `homework`) or jump; was <Plug>luasnip-jump-next with blink
          return require("luasnip").expand_or_locally_jumpable() and "<Plug>luasnip-expand-or-jump"
        end,
        expr = true,
        silent = true,
        mode = "i",
      },
      { "fj", function() return require("luasnip").jump(1) end, mode = "s" },
      { "fk", function() require("luasnip").jump(-1) end, mode = { "i", "s" } },
      { "<c-h>", "<Plug>luasnip-next-choice", mode = { "i", "s" } },
      { "<c-p>", "<Plug>luasnip-prev-choice", mode = { "i", "s" } },
    },
  },
}
