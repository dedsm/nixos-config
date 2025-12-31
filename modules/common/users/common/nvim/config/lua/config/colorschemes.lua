vim.opt.termguicolors = true
vim.cmd.colorscheme "solarized"

-- Auto dark mode detection (macOS only)
if vim.fn.has('macunix') == 1 then
    require('dark_notify').run()
end

-- Manual toggle with <leader>b
vim.keymap.set({"n"}, "<leader>b", function()
    if vim.fn.has('macunix') == 1 then
        require('dark_notify').toggle()
    else
        local background = vim.o.background
        if background == "light" then
            vim.o.background = "dark"
        else
            vim.o.background = "light"
        end
    end
end)
