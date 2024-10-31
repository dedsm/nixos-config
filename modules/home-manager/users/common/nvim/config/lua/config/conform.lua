local conform = require('conform')

conform.setup({
  formatters_by_ft = {
    python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
    ruby = { "rubocop" },
    markdown = { "pandoc" },
    nix = { "alejandra" }
  },
  formatters = {
    pandoc = {
      command = "pandoc",
      -- A list of strings, or a function that returns a list of strings
      -- Return a single string instead of a list to run the command in a shell
      args = { "-f", "gfm", "-t", "gfm", "-s", "$FILENAME"},
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
