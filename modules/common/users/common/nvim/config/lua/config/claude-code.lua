require("claude-code").setup({
  window = {
    position = "vertical",
    split_ratio = 0.4,
  },
})

vim.keymap.set("n", "<leader>cc", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude Code" })
vim.keymap.set("n", "<leader>cR", "<cmd>ClaudeCodeResume<cr>", { desc = "Toggle Claude Code Resume picker" })
