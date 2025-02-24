require('avante_lib').load()
local avante = require('avante')

avante.setup({
    provider = "gemini",
    auto_suggestions_provider = "gemini",
    cursor_applying_provider = "gemini",
    gemini = {
        model = "gemini-2.0-flash-thinking-exp-01-21",
    },
})
