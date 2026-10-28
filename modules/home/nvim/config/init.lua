vim.g.mapleader = "\\"
vim.g.maplocalleader = "\\"


-- Make line numbers default
vim.opt.number = true

-- No mouse for me
vim.opt.mouse = ""

-- Mode is in the status line
vim.opt.showmode = false

-- Same clipboard as OS
vim.opt.clipboard = "unnamedplus"

-- Continue wrapped lines in same indentation level
vim.opt.breakindent = true
vim.opt.wrap = false

-- Backup

vim.opt.backup = false
vim.opt.wb = false
vim.opt.swapfile = false

-- Undo

vim.opt.undodir = vim.fn.stdpath("data") .. "/undodir"
vim.opt.undofile = true
vim.opt.undolevels = 1000
vim.opt.undoreload = 10000

-- Visual aids
vim.opt.colorcolumn = "120"
vim.opt.signcolumn = "yes"

-- Decrease update time
vim.opt.updatetime = 250

-- Split positions
vim.opt.splitright = false
vim.opt.splitbelow = true

--
vim.opt.incsearch = true
vim.opt.inccommand = 'split'

-- Scroll before getting to the end
vim.opt.scrolloff = 7
vim.opt.sidescroll = 1
vim.opt.sidescrolloff = 10

require("config.mappings")
require("config.neo_tree")
require("config.telescope")
require("config.fidget")
require("config.conform")
require("config.mini")
require("config.colorschemes")
require('config.lint')
require('config.treesiter')

require("config.diagnostics")

require("config.lsp")
require("config.cmp")
require("config.claude-code")
