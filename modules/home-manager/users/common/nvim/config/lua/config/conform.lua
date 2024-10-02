local conform = require('conform')

conform.setup({
  formatters_by_ft = {
    python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
    ruby = { "rubocop" },
    markdown = { "markdownlint-cli2" },
    nix = { "alejandra" }
  },
  formatters = {
    rubocop = {
      args = { "-a", "-f", "quiet", "--stderr", "--stdin", "$FILENAME" }
    }
  }
})

vim.keymap.set({ "n" }, "<leader>f", function()
  conform.format { async = true, lsp_format = "fallback" }
end, { desc = "[F]ormat buffer" })
