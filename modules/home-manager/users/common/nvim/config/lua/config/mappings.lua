vim.keymap.set("n", ";", ":")

vim.keymap.set({ "n", "i", "v" }, "<up>", "<nop>")
vim.keymap.set({ "n", "i", "v" }, "<down>", "<nop>")
vim.keymap.set({ "n", "i", "v" }, "<left>", "<nop>")
vim.keymap.set({ "n", "i", "v" }, "<right>", "<nop>")

vim.keymap.set({ "n" }, "<leader><space>", vim.cmd.noh, { desc = "<space> Clear Search Highlights" })

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})
