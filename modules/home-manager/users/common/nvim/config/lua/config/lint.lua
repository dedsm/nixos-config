local lint = require('lint')

lint.linters_by_ft['markdown'] = { 'markdownlint' }
lint.linters_by_ft['dockerfile'] = { 'hadolint' }
lint.linters_by_ft['python'] = { 'ruff' }

vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "InsertLeave" }, {
  callback = function()

    -- try_lint without arguments runs the linters defined in `linters_by_ft`
    -- for the current filetype
    lint.try_lint()
  end,
})
