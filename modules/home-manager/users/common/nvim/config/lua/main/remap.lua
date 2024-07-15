vim.g.mapleader = "\\"

vim.keymap.set("n", ";", ":")

vim.keymap.set("n", "<F3>", vim.cmd.NERDTreeToggle)

vim.keymap.set({ "n", "i", "v" }, "<up>", "<nop>")
vim.keymap.set({ "n", "i", "v" }, "<down>", "<nop>")
vim.keymap.set({ "n", "i", "v" }, "<left>", "<nop>")
vim.keymap.set({ "n", "i", "v" }, "<right>", "<nop>")

vim.keymap.set({ "n" }, "<leader><space>", vim.cmd.noh)

vim.keymap.set({ "n" }, "<leader>f", function()
    vim.cmd.ALEFix()
end)

vim.keymap.set({ "n" }, "<leader>gd", vim.lsp.buf.definition)
vim.keymap.set({ "n" }, "<leader>gD", vim.lsp.buf.declaration)
vim.keymap.set({ "n" }, "<leader>gi", vim.lsp.buf.implementation)
vim.keymap.set({ "n" }, "<leader>go", vim.lsp.buf.type_definition)
vim.keymap.set({ "n" }, "<leader>gr", vim.lsp.buf.references)
vim.keymap.set({ "n" }, "<leader>gs", vim.lsp.buf.signature_help)
vim.keymap.set({ "n" }, "<leader>k", vim.lsp.buf.hover)
vim.keymap.set({ "n" }, "<leader>R", vim.lsp.buf.rename)
