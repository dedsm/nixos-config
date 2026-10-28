vim.keymap.set("n", "<F3>", function ()
    vim.cmd.Neotree("reveal", "toggle")
end)

require('neo-tree').setup({
    git_status_async = true,
    filesystem = {
        filtered_items = {
            hide_dotfiles = false,
            hide_git_ignored = false,
        },
        use_libuv_file_watcher = true
    },
})
