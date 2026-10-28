vim.opt.termguicolors = true
vim.cmd.colorscheme "solarized"

-- Auto dark mode detection. macOS only: dark_notify spawns a `dark-notify`
-- binary that exists only there. On Linux the TUI queries the terminal
-- background (OSC 11) at startup and sets 'background' itself, so nvim follows
-- foot's palette without any plugin.
if vim.fn.has('macunix') == 1 then
    require('dark_notify').run()
end

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
