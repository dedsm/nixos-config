vim.cmd('filetype plugin indent on')
vim.cmd('syntax on')

vim.o.mouse = ""
vim.o.wrap = false
vim.o.compatible = false
vim.o.ls = 2

vim.o.clipboard = "unnamedplus"
vim.o.tabstop=4
vim.o.softtabstop=4
vim.o.shiftwidth=4
vim.o.showmode = true
vim.o.incsearch = true
vim.o.ruler = true
vim.o.number = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.ttyfast = true
vim.o.so=7
vim.o.ss=1
vim.o.siso=10
vim.o.expandtab = true
vim.o.sm = true

vim.o.colorcolumn = "120"
vim.o.signcolumn = "yes"

vim.o.nu = true

-- Backup

vim.o.backup = false
vim.o.wb = false
vim.o.swapfile = false

-- Undo

vim.o.undodir="/home/david/.local/share/nvim/undodir"
vim.o.undofile = true
vim.o.undolevels = 1000
vim.o.undoreload = 10000

-- Remove trailing whitespace from certain files

vim.cmd([[autocmd FileType c,cpp,python,ruby autocmd BufWritePre <buffer> :%s/\s\+$//e]])
