local lspconfig = require('lspconfig')

lspconfig.solargraph.setup {
  on_attach = function(_, _) print('hello solargraph') end,
  cmd = { "bundle", "exec", "solargraph", "stdio" }
}
