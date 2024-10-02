vim.opt.termguicolors = true
vim.cmd.colorscheme "solarized"

vim.opt.background = "light"

vim.keymap.set({"n"}, "<leader>b", function()
    local background = vim.o.background
    if background == "light" then
        vim.o.background = "dark"
    else
        vim.o.background = "light"
    end
end)
