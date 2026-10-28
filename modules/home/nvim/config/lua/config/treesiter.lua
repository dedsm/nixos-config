-- Since parsers are installed via Nix with withAllGrammars,
-- we just need to enable treesitter features via autocmds

-- Enable treesitter highlighting and indentation for all filetypes
-- Use pcall to gracefully handle filetypes without parsers (like neo-tree)
vim.api.nvim_create_autocmd('FileType', {
  pattern = '*',
  callback = function()
    local ok = pcall(vim.treesitter.start)
    if ok then
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
    -- Silently ignore filetypes without parsers
  end,
})
