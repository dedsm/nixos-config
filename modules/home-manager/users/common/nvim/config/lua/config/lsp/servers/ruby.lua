vim.lsp.config.ruby_lsp = {
  on_attach = function(_, _) print('hello lsp') end,
}

vim.lsp.enable('ruby_lsp')
