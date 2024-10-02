require('copilot').setup({
    suggestion = { enabled = true, auto_trigger = false },
    panel = { enabled = false },
})
require('copilot_cmp').setup()

require("CopilotChat").setup {
    debug = true,
}

vim.keymap.set({ "n", "v", "i" }, "<leader>cx", function()
    local actions = require("CopilotChat.actions")
    require("CopilotChat.integrations.telescope").pick(actions.prompt_actions())
end)
