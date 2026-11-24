-- only kept so `require("luasnip.extras.filetype_functions")` keeps working
return {
  from_filetype = function() return vim.split(vim.bo.filetype, ".", { plain = true }) end,
}
