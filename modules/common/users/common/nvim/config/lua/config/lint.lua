local lint = require('lint')

lint.linters_by_ft['markdown'] = { 'markdownlint' }
lint.linters_by_ft['dockerfile'] = { 'hadolint' }
lint.linters_by_ft['python'] = { 'ruff' }
lint.linters_by_ft['text'] = {  }

vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "InsertLeave" }, {
  callback = function()

    -- try_lint without arguments runs the linters defined in `linters_by_ft`
    -- for the current filetype
    lint.try_lint(nil, { ignore_errors = true })
  end,
})

-- Show linters for the current buffer's file type
vim.api.nvim_create_user_command("LintInfo", function()
  local filetype = vim.bo.filetype
  local linters = require("lint").linters_by_ft[filetype]

  if linters then
    print("Linters for " .. filetype .. ": " .. table.concat(linters, ", "))
  else
    print("No linters configured for filetype: " .. filetype)
  end
end, {})
