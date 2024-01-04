vim.g.ale_disable_lsp = true
vim.g.ale_use_neovim_diagnostics_api = true

vim.g.ale_linters = {
    ruby = {},
    python = {'bandit', 'flake8', 'mypy'},
    nix = {'nixfmt'}
}

vim.g.ale_fixers = {
    ["*"] = {"remove_trailing_lines", "trim_whitespace"},
    lua = {"lua-format"},
    markdown = {'pandoc'},
    python = {'black', 'isort'},
    ruby = {'rubocop'},
    rust = {'rustfmt'},
    nix = {'nixfmt'}
}

vim.g.ale_markdown_pandoc_options = "--columns 120 -f gfm -t gfm -s -"
