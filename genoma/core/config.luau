--!strict
-- What the person chose: ~/.config/floema/config.json, each key a signal a
-- binding follows. The settings cell (ui/settings_cell.luau) and the keys
-- (Ctrl+= / Ctrl+- / Ctrl+0 for the size) write it.
local g = require("@genoma")

local M = {}

local dir = (g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")) .. "/floema"
M.path = dir .. "/config.json"

M.SIZE_MIN, M.SIZE_MAX = 9, 32

M.defaults = {
    -- The size of the letters in the grid (Akusen, 2026-11-26: Space Mono
    -- at 15), the person's to set and kept.
    font_size = 15,
    -- The cursor leaving a trail as it moves (ui/cursor.luau).
    cursor_trail = true,
    -- A command that ended where it was not seen is told after this long,
    -- seconds; 0, never.
    notify_after = 10,
} :: { [string]: any }

local CHOICES: { [string]: { any } } = {
    notify_after = { 0, 10, 30, 60 },
}

local file = g.file { path = M.path, watch = false }

local function valid(key: string, value: any): boolean
    if M.defaults[key] == nil or type(value) ~= type(M.defaults[key]) then return false end
    local choices = CHOICES[key]
    return choices == nil or table.find(choices, value) ~= nil
end

local function shaped(key: string, value: any): any
    if key == "font_size" then return math.clamp(math.floor(value + 0.5), M.SIZE_MIN, M.SIZE_MAX) end
    return value
end

-- What was read and is not ours stays in the file: a newer Floema's key is
-- not lost by an older one.
local kept: { [string]: any } = {}
local signals: { [string]: any } = {}
do
    if file.text then
        local ok, parsed = pcall(g.parse_json, file.text)
        if ok and type(parsed) == "table" then kept = parsed end
    end
    for key, default in M.defaults do
        local value = kept[key]
        if not valid(key, value) then value = default end
        signals[key] = g.signal(shaped(key, value))
    end
end

function M.get(key: string): any return signals[key].value end

local saving: any = nil
function M.set(key: string, value: any)
    if not valid(key, value) then return end
    value = shaped(key, value)
    if g.untracked(function() return signals[key].value end) == value then return end
    signals[key].value = value
    -- Ctrl+= held, or a slider dragged, is one write, not fifty.
    if saving then saving:stop() end
    saving = g.after(0.5, function()
        saving = nil
        local out = table.clone(kept)
        for k, s in signals do out[k] = g.untracked(function() return s.value end) end
        file:write(g.to_json(out, true))
    end)
end

return M
