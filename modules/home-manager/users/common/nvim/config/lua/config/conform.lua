local conform = require('conform')

conform.setup({
  formatters_by_ft = {
    python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
    ruby = { "rubocop" },
    markdown = { "pandoc_markdown" },
    nix = { "alejandra" },
  },
  formatters = {
    pandoc_markdown = {
      command = "pandoc",
      -- A list of strings, or a function that returns a list of strings
      -- Return a single string instead of a list to run the command in a shell
      args = { "-f", "markdow", "-t", "markdown", "-s", "$FILENAME" },
      stdin = true
    },
    rubocop = {
      args = { "-a", "-f", "quiet", "--stderr", "--stdin", "$FILENAME" }
    }
  }
})

vim.keymap.set({ "n" }, "<leader>f", function()
  conform.format { async = true, lsp_format = "fallback" }
end, { desc = "[F]ormat buffer" })
