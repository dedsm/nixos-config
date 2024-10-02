local lspconfig = require('lspconfig')

lspconfig.lua_ls.setup {}
lazydev = require('lazydev').setup({
  library = {
    "luvit-meta/library"
  }
})
