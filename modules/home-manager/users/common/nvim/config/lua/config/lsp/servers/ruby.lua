local lspconfig = require('lspconfig')

lspconfig.ruby_lsp.setup {
  on_attach = function(_, _) print('hello lsp') end,
}
