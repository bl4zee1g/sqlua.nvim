local utils = require("sqlua.utils")
local Connection = require("sqlua.connection")
local UI = require("sqlua.ui")

local M = {}

-- ~/.local/share/nvim/sqlua
SQLUA_ROOT_DIR = utils.concat({
    vim.fn.stdpath("data"),
    "sqlua",
})

DEFAULT_CONFIG = {
    db_save_location = utils.concat({ SQLUA_ROOT_DIR, "dbs" }),
    connections_save_location = utils.concat({ SQLUA_ROOT_DIR, "connections.json" }),
    default_limit = 200,
    load_connections_on_start = false,
    syntax_highlighting = false,
    keybinds = {
        execute_query = "<leader>r",
        activate_db = "<C-a>",
        insert_execute_query = "<C-r>",
    },
}

-- Shared, mutable state read by command closures at *invocation* time
-- (not captured once at registration time). This makes `M.setup` safe to
-- call more than once (e.g. once from plugin/sqlua.lua's bootstrap command
-- and once from a lazy.nvim `config` function) regardless of call order:
-- whichever caller passes real opts always wins, and the user commands are
-- only ever registered once so the very first `:SQLua` invocation always
-- works instead of silently no-opping.
local state = {
    config = vim.deepcopy(DEFAULT_CONFIG),
    commands_registered = false,
}

M.setup = function(opts)
    state.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
    local config = state.config

    -- creating root directory
    vim.fn.mkdir(SQLUA_ROOT_DIR, "p")

    -- creating config json
    local connections_file = utils.concat({
        vim.fn.stdpath("data"),
        "sqlua",
        "connections.json",
    })
    if vim.fn.filereadable(connections_file) == 0 then Connection.write({}) end

    if state.commands_registered then return end
    state.commands_registered = true

    -- main function to enter the UI
    vim.api.nvim_create_user_command("SQLua", function(args)
        local cfg = state.config
        UI:setup(cfg)
        UI.initial_layout_loaded = true

        local cons = Connection.read()
        for _, con in pairs(cons) do
            local name, url = con["name"], con["url"]
            vim.fn.mkdir(SQLUA_ROOT_DIR .. "/" .. name, "p")
            local connection = Connection.setup(name, url, UI.options)
            if cfg.load_connections_on_start and connection then connection:connect() end
            UI.dbs[name] = connection
        end

        -- UI.connections_loaded = true
        if UI.num_dbs > 0 then vim.api.nvim_win_set_cursor(UI.windows.sidebar, { 2, 2 }) end
        UI:refreshSidebar()
    end, { nargs = "?" })

    vim.api.nvim_create_user_command("SQLuaEdit", function() vim.cmd("e " .. CONNECTIONS_FILE) end, {})

    vim.api.nvim_create_user_command("SQLuaAddConnection", function()
        -- TODO: add floating window to edit connections file on the spot
        local url = vim.fn.input("Enter the connection url: ")
        -- TODO: verify url string
        local name = vim.fn.input("Enter the name for the connection: ")
        Connection.add(url, name)
        local cfg = state.config
        local dbs = utils.getDatabases(cfg.connections_save_location)
        for _, db in pairs(dbs) do
            local connection = Connection.setup(db.name, db.url, cfg)
            if cfg.load_connections_on_start and connection then connection:connect() end
        end
        UI:refreshSidebar()
        if UI.num_dbs > 0 then vim.api.nvim_win_set_cursor(UI.windows.sidebar, { 2, 2 }) end
    end, {})

    -- Attach the current buffer to sqlua's editor tracking, so the
    -- execute-query keybind works on it and it shows under "Buffers" even
    -- though it wasn't created via "New Editor" or the file tree.
    vim.api.nvim_create_user_command("SQLuaAttachBuffer", function()
        if not UI.initial_layout_loaded then
            vim.notify("Run :SQLua first", vim.log.levels.WARN)
            return
        end
        local buf = vim.api.nvim_get_current_buf()
        if not vim.tbl_contains(UI.buffers.editors, buf) then
            table.insert(UI.buffers.editors, buf)
        end
        UI:refreshSidebar()
    end, {})
end

return M
