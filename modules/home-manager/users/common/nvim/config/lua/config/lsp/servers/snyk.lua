local lspconfig = require('lspconfig')

lspconfig.snyk_ls.setup {
  filetypes = { "ruby", "dockerfile", "go", "gomod", "haml", "javascript", "typescript", "json", "python", "requirements", "helm", "yaml", "terraform", "terraform-vars" },

  cmd = { 'snyk-ls', '-l', 'debug' },

  init_options = {
    activateSnykOpenSource = 'true',
    activateSnykCode = 'true',
    activateSnykIaC = 'false',
    manageBinariesAutomatically = 'false',
    authenticationMethod = 'token',
    additionalParams = '--all-projects',
    cliPath = "/etc/profiles/per-user/david/bin/snyk",
  },
}
