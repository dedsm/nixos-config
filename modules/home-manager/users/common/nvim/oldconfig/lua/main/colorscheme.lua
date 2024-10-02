vim.o.termguicolors=true
vim.o.background = "light"
vim.cmd('colorscheme solarized-high')

vim.keymap.set({"n"}, "<leader>b", function()
    local background = vim.o.background
    if background == "light" then
        vim.o.background = "dark"
    else
        vim.o.background = "light"
    end
end)
