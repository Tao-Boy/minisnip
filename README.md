# minisnip

按照 [Fireond/dotfiles](https://github.com/Fireond/dotfiles/tree/main/nvim/.config/nvim/LuaSnip) 实际用到的功能，从 [LuaSnip](https://github.com/L3MON4D3/LuaSnip) 精简出来的 snippet 引擎。

- LuaSnip：81 个文件，约 19 700 行 Lua
- minisnip：核心 7 个文件，约 1 150 行（另有 12 行的 `luasnip.*` 兼容模块）

提供了 `require("luasnip")`、`require("luasnip.extras.fmt")` 等兼容模块，**原有的 42 个 snippet 文件（1034 个 autosnippet、40 个普通 snippet）一行都不用改**。

在源码编译的 Neovim 0.12.6 上测试通过（0.9.5 上也能跑）。

## 保留了什么

只保留 dotfiles 里真正用到的部分：

| 功能 | dotfiles 中的用法 |
| --- | --- |
| `s` / `t` / `i` / `f` / `d` / `sn` / `c` / `r` | 所有 snippet 文件 |
| `fmt`、`fmta`（dedent、trim_empty、`<>` 分隔符、重复占位符） | 523 处 `fmta`，1 处 `fmt` |
| `rep`、`lambda`（`l._1:match(...):gsub(...)`） | `lua.lua` 等 |
| 触发选项 `trig`、`regTrig`（Lua pattern + `captures`）、`wordTrig`、`priority`、`snippetType = "autosnippet"`、`condition`、`dscr`/`desc` | 所有文件 |
| 条件对象 `line_begin`、`line_end`，以及 `*`、`+`、`-` 组合（`tex.in_text * line_begin`） | 约 100 处 |
| `parent.snippet.env.SELECT_RAW`、`parent.trigger`、`snip.captures` | `get_visual`、`py.lua` |
| `store_selection_keys`（可视模式剪切选区，供 `SELECT_RAW` 使用） | `` "`" `` |
| `update_events`（`rep` 和函数节点实时更新） | `TextChanged`, `TextChangedI` |
| `restore_node` + `choice_node` 的 `restore_cursor` | `tex/env.lua` 中 equation/equation* 切换 |
| `filetype_extend` | `tex`/`markdown` → `tex_shared` |
| `loaders.from_lua.load({ paths = ... })`，保存后自动重新加载 | `luasnip.lua` |
| `loaders.edit_snippet_files()` | `<leader>gs` |
| `expand_auto`（可被覆盖，dotfiles 用它插入撤销断点）、`expand_or_locally_jumpable`、`jump`、`jumpable`、`change_choice` | `luasnip.lua` |
| `<Plug>luasnip-jump-next` / `-jump-prev` / `-next-choice` / `-prev-choice` / `-expand-or-jump` | 按键映射 |
| `ls.parser.parse_snippet`（`$1`、`${1:text}`、`$0`、转义、重复 tabstop） | `lua.lua` |
| 嵌套 snippet（在占位符里继续触发 autosnippet） | 写公式时最常见的用法 |

## 去掉了什么

LuaSnip 中 dotfiles 没用到的部分全部删除：

- `from_vscode`、`from_snipmate` 加载器、friendly-snippets 支持、按文件类型懒加载、文件系统监听
- jsregexp / ECMAScript 与 vim regex 触发引擎（只保留 Lua pattern）
- `postfix`、`treesitter_postfix`、`otf`、`select_choice`、`snippet_list`、`snip_location`、`dynamic_lambda`、`partial`、`match`、`nonempty` 等 extras
- `ext_opts` 高亮、`luasnip.util.types`、节点事件与回调（`callbacks`、`User` autocmd）
- `history` / `keep_roots` / `link_children`、`region_check_events`、`delete_check_events`
- `multiSnippet`、`snippetProxy`、absolute/key indexer、`exit_out_of_region`、`cleanup`、`invalidate`
- 补全引擎集成（blink.cmp / nvim-cmp 源、`lsp_expand`）、docstring、snippet id
- LSP snippet 语法里的 choice、变量、transform
- 内置变量只保留选区相关的 `SELECT_RAW` 等

## 安装（LazyVim）

1. 在 `lazyvim.json` 里删掉 `"lazyvim.plugins.extras.coding.luasnip"`，否则 LazyVim 会继续安装原版 LuaSnip。
2. 用 [`examples/lazyvim.lua`](examples/lazyvim.lua) 替换 `lua/plugins/default/luasnip.lua`。配置和原来一样，只改了三处：
   - 插件名换成 `tao-boy/minisnip`；
   - 加了 `event = "InsertEnter"`，一进入插入模式 autosnippet 就能用；
   - 插入模式的 `fj` 改为 `<Plug>luasnip-expand-or-jump`：minisnip 不接入补全菜单，40 个普通 snippet（`homework`、`note`、`iso` 等）要靠输入触发词后按 `fj` 展开。

`require("luasnip.loaders").edit_snippet_files({})` 等现有调用可以保持不变。

## 用法

和 LuaSnip 写法完全一致：

```lua
local ls = require("luasnip") -- 等同 require("minisnip")
local s, t, i, f, d, sn, c, r = ls.s, ls.t, ls.i, ls.f, ls.d, ls.sn, ls.c, ls.r
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep
local line_begin = require("luasnip.extras.expand_conditions").line_begin

return {
  s({ trig = "beg", snippetType = "autosnippet" },
    fmta([[
      \begin{<>}
        <>
      \end{<>}
    ]], { i(1), i(0), rep(1) }),
    { condition = line_begin }),
}
```

snippet 文件放在 `<path>/<filetype>.lua` 或 `<path>/<filetype>/*.lua`，可以 `return snippets, autosnippets`，也可以只返回一个表、用 `snippetType` 区分。

## 和 LuaSnip 的行为差异

- 没有 history：跳过根 snippet 的 `$0` 之后再往前跳不会回到旧 snippet。
- 嵌套 snippet 在第一个节点上往回跳时退出，并选中外层的占位符。
- 只有文本选项的 choice 节点获得焦点时，光标放在选项文本末尾。
- 不提供补全引擎（blink.cmp / nvim-cmp）的 snippet 源，LSP 补全里的 snippet 交给补全引擎自己处理。

## 测试

```bash
nvim --headless -u NONE -c "luafile tests/run.lua"
```

测试通过 `nvim_input` 模拟真实按键，会触发 `InsertCharPre`/`TextChangedI`，覆盖 autosnippet、嵌套、跳转、`rep`、`regTrig`、choice/restore、选区、`lambda`、`parse_snippet` 等。另外，dotfiles 的全部 42 个 snippet 文件也在本地加载并逐个展开过（`util.latex` 用桩代替）。

## 许可

MIT，见 [LICENSE](LICENSE)。部分逻辑移植自 LuaSnip（Apache-2.0），见 [NOTICE](NOTICE)。
