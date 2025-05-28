vim.diagnostic.config({
  virtual_text = {
    prefix = "●", -- Or "▸", "→", etc.
    spacing = 1, -- Add a space after the prefix
    source = "always", -- Show source only if multiple sources for a diagnostic
    severity_filter = vim.diagnostic.severity.WARNING, -- Only show virtual text for warnings and errors
  },
  signs = true, -- Keep signs enabled
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    source = "always", -- Show source in float
    border = "rounded",
    max_width = 80, -- Limit float width
  }
})

-- Show diagnostics in a floating window on CursorHold
vim.api.nvim_create_autocmd("CursorHold", {
  pattern = "*",
  group = vim.api.nvim_create_augroup("show_diagnostics_on_hold", { clear = true }),
  callback = function()
    vim.diagnostic.open_float(nil, {
      scope = "cursor", -- Or "line" to show all diagnostics on the line
      focusable = false, -- Prevent the float from taking focus
    })
  end
})

-- Keymaps for diagnostics
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic' })
vim.keymap.set('n', '<leader>de', vim.diagnostic.open_float, { desc = 'Show diagnostic float' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })