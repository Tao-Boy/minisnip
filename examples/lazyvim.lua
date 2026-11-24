-- Drop-in replacement for nvim/.config/nvim/lua/plugins/default/luasnip.lua
-- Also remove "lazyvim.plugins.extras.coding.luasnip" from lazyvim.json,
-- otherwise LazyVim keeps installing the real LuaSnip.
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
      -- what LazyVim's luasnip extra used to provide (<Tab> / <Esc> handling in blink)
      if _G.LazyVim then
        LazyVim.cmp.actions.snippet_forward = function()
          if ls.jumpable(1) then
            vim.schedule(function() ls.jump(1) end)
            return true
          end
        end
        LazyVim.cmp.actions.snippet_stop = function()
          if ls.jumpable(1) then
            ls.unlink_current()
            return true
          end
        end
      end
    end,
    keys = {
      {
        "fj",
        function()
          return require("luasnip").expand_or_locally_jumpable() and "<Plug>luasnip-jump-next"
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
  {
    "saghen/blink.cmp",
    opts = {
      -- LSP snippets are expanded/jumped by minisnip too
      snippets = {
        expand = function(body) require("minisnip").lsp_expand(body) end,
        active = function(filter) return require("minisnip").jumpable(filter and filter.direction or 1) end,
        jump = function(dir) require("minisnip").jump(dir) end,
      },
      sources = {
        providers = {
          snippets = { module = "minisnip.blink", opts = { show_autosnippets = false } },
        },
      },
    },
  },
}
