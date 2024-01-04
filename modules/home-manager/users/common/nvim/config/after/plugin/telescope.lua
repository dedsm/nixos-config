local telescope = require("telescope")
local builtin = require("telescope.builtin")

vim.keymap.set('n', '<C-p>', builtin.find_files, {})
vim.keymap.set("n", "<leader>s", builtin.live_grep, {})

telescope.setup({
    defaults = {
        preview = {
            treesitter = false,
        },
    },
})

telescope.load_extension('fzf')
