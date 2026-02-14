vim.opt.termguicolors = true
vim.cmd.colorscheme "solarized"

-- Auto dark mode detection (macOS via dark-notify, Linux via darkman)
require('dark_notify').run()

-- Manual toggle with <leader>b
vim.keymap.set({"n"}, "<leader>b", function()
    local background = vim.o.background
    if background == "light" then
        vim.o.background = "dark"
    else
        vim.o.background = "light"
    end
    
    -- If on Darwin, also try to notify the system or plugin
    if vim.fn.has('macunix') == 1 then
        require('dark_notify').toggle()
    end
end)
