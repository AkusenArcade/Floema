--!strict
-- Floema as the desktop's terminal (docs/plan.md §2): what Rizoma's F4,
-- Bioma's launcher and keys, and every Genoma app open
-- (apps:terminal) when they ask for "the terminal". They ask
-- xdg-terminal-exec first, which reads the terminals the person prefers,
-- in order, from $XDG_CONFIG_HOME/xdg-terminals.list: Floema switched on is
-- Floema at the head of that list, switched off it is taken out of it and
-- the others are left as they were.
local g = require("@genoma")
local apps = require("@genoma/apps")

local M = {}

M.ID = "dev.akusen.floema"
local ENTRY = M.ID .. ".desktop"

local config = g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")
local file = g.file { path = config .. "/xdg-terminals.list" }

-- Whether xdg-terminal-exec is there to read the list: without it the
-- desktop's terminal is $TERMINAL, or the first of the usual ones.
M.reader = g.signal(true)
pcall(function()
    g.process {
        command = { "sh", "-c", "command -v xdg-terminal-exec" },
        on_exit = function(code: number) M.reader.value = code == 0 end,
    }
end)

-- The list's lines that name a terminal.
local function named(text: string?): { string }
    local out: { string } = {}
    for line in string.gmatch(text or "", "[^\n]+") do
        local entry = string.match(line, "^%s*(.-)%s*$") or ""
        if entry ~= "" and string.sub(entry, 1, 1) ~= "#" then table.insert(out, entry) end
    end
    return out
end

-- Installed, so that it can be found by its entry.
function M.can_be_default(): boolean return apps:find(M.ID) ~= nil end

function M.is_default(): boolean
    local list = named(file.text)
    -- (An entry may carry an action, `id.desktop:action`.)
    return list[1] ~= nil and string.match(list[1], "^[^:]+") == ENTRY
end

function M.set_default(on: boolean)
    local out: { string } = {}
    -- What the person wrote stays, comments too; only Floema's line moves.
    for line in string.gmatch(file.text or "", "[^\n]+") do
        local entry = string.match(line, "^%s*(.-)%s*$") or ""
        if string.match(entry, "^[^:]+") ~= ENTRY then table.insert(out, line) end
    end
    if on then
        -- At the head of what names a terminal, after the comments above it.
        local at = 1
        while at <= #out and (string.match(out[at], "^%s*#") or string.match(out[at], "^%s*$")) do at += 1 end
        table.insert(out, at, ENTRY)
    end
    file:write(table.concat(out, "\n") .. (if #out > 0 then "\n" else ""))
end

return M
