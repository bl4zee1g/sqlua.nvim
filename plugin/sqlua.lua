if vim.g.loaded_sqlua then
    return
end

vim.g.loaded_sqlua = true

require("sqlua").setup()
