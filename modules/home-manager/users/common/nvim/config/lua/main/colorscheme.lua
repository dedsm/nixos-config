vim.o.termguicolors=true
vim.o.t_Co=256
vim.cmd('colorscheme NeoSolarized')
vim.o.background = "light"
vim.g.neosolarized_visibility = "high"

vim.keymap.set({"n"}, "<leader>b", function()
    local background = vim.o.background
    if background == "light" then
        vim.o.background = "dark"
    else
        vim.o.background = "light"
    end
end)
