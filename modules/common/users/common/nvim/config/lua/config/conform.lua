local conform = require('conform')

conform.setup({
  formatters_by_ft = {
    python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
    ruby = { "rubocop" },
    markdown = { "mdformat" },
    nix = { "alejandra" },
  },
  formatters = {
    rubocop = {
      args = { "-a", "-f", "quiet", "--stderr", "--stdin", "$FILENAME" },
      cwd = function(ctx)
        local current_bufnr = vim.api.nvim_get_current_buf()
        local filepath = vim.api.nvim_buf_get_name(current_bufnr)
        if not filepath or filepath == "" then
          -- No file path associated with the buffer (e.g., new, unnamed buffer)
          return nil
        end

        local current_file_dir = vim.fs.dirname(filepath)
        if not current_file_dir then
          -- Should be rare if filepath is valid, but as a fallback.
          return nil
        end

        -- 1. Check for Gemfile in 'application' subdirectory
        local application_dir_path = current_file_dir .. "/application"
        -- Handle case where current_file_dir is the root "/"
        if current_file_dir == "/" then
          application_dir_path = "/application"
        end
        local application_gemfile_path = application_dir_path .. "/Gemfile"

        if vim.uv.fs_stat(application_gemfile_path) then -- vim.uv is preferred over vim.loop for new code
          return application_dir_path
        end

        -- 2. If not in 'application/', search upwards for Gemfile from the file's path
        local upward_gemfile_paths = vim.fs.find({ 'Gemfile' }, { upward = true, path = filepath, type = 'file' })
        if #upward_gemfile_paths > 0 then
          return vim.fs.dirname(upward_gemfile_paths[1])
        end

        -- 3. Fallback to current file's directory if no Gemfile is found
        return current_file_dir
      end
    }
  }
})

vim.keymap.set({ "n" }, "<leader>f", function()
  conform.format { async = true, lsp_format = "fallback" }
end, { desc = "[F]ormat buffer" })
