-- Automatic comments
require("mini.comment").setup()

-- Autopairs
require("mini.pairs").setup()

-- Extend text selection
require("mini.ai").setup { n_lines = 500 }

-- Surround text with symbol
require("mini.surround").setup()

-- Eye candy
require("mini.animate").setup()

-- Trailing space
require("mini.trailspace").setup()

vim.api.nvim_create_autocmd({ "InsertLeave" }, {
  callback = function ()
    if not vim.bo.modifiable then
      return
    end
    MiniTrailspace.trim()
    MiniTrailspace.trim_last_lines()
  end
})

-- Status Line
local statusline = require("mini.statusline")

statusline.setup { use_icons = true }

---@diagnostic disable-next-line: duplicate-set-field
statusline.section_location = function()
  return "%2l:%-2v"
end
