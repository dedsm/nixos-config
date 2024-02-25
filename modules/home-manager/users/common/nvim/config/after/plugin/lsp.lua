local lsp = require('lsp-zero').preset({
    name = 'recommended',
    set_lsp_keymaps = true,
    manage_nvim_cmp = true,
    suggest_lsp_servers = true
})

local lspconfig = require('lspconfig')


lsp.configure('jedi_language_server', {})

lsp.configure('lua_ls', {
    cmd = require('lspcontainers').command('lua_ls'),
    settings = {
        Lua = {
            runtime = { version = 'LuaJIT' },
            diagnostics = { globals = { 'vim' } },
            workspace = { library = vim.api.nvim_get_runtime_file("", true) },
            telemetry = { enable = false }
        }
    }
})

lsp.configure('marksman', {})

lsp.configure('solargraph', {
    on_attach = function(client, bufnr) print('hello solargraph') end,
    cmd = { "bundle", "exec", "solargraph", "stdio" }
})

lsp.configure('tsserver', {})
lsp.configure('svelte', {})
lsp.configure('gopls', {})
lsp.configure('rust_analyzer', {})


lsp.setup()

local has_words_before = function()
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local luasnip = require("luasnip")
local cmp = require("cmp")

cmp.setup({
    sources = {
        { name = 'copilot', keyword_length = 0 },
        { name = 'nvim_lsp' },
        { name = 'luasnip' },
        { name = 'path' },
    },
    mapping = cmp.mapping.preset.insert({
            ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
                cmp.select_next_item()
                -- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
                -- that way you will only jump inside the snippet region
            elseif luasnip.expand_or_jumpable() then
                luasnip.expand_or_jump()
            elseif has_words_before() then
                cmp.complete()
            else
                fallback()
            end
        end, { "i", "s" }),
            ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
                cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
                luasnip.jump(-1)
            else
                fallback()
            end
        end, { "i", "s" }),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-Enter>'] = cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true }),
    }),
    preselect = 'none',
    completion = { completeopt = 'menu,menuone,noinsert,noselect' },
    select_behavior = 'insert'
})

vim.diagnostic.config({
    virtual_text = true,
    signs = true,
    update_in_insert = false,
    underline = true,
    severity_sort = false,
    float = true
})
