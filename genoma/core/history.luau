--!strict
-- The commands run in each folder, kept by Floema itself (docs/plan.md §6):
-- every command reaches it with the folder it was typed in, so the folder's
-- commands panel can offer the most used there first. Kept in
-- $XDG_STATE_HOME/floema/history.json; a command typed after a space is the
-- shell's to forget, and is not kept.
local g = require("@genoma")

local M = {}

export type Entry = { text: string, count: number, last: number }

-- What one folder keeps at most: the least used and oldest go first.
local KEEP = 100

local state = g.env("XDG_STATE_HOME")
if state == nil or state == "" then state = (g.env("HOME") or "") .. "/.local/state" end
local file = g.file { path = state .. "/floema/history.json", watch = false }

local folders: { [string]: { Entry } } = {}
do
    local text = file.text
    if text then
        local ok, parsed = pcall(g.parse_json, text)
        if ok and type(parsed) == "table" then
            for folder, list in parsed do
                if type(folder) ~= "string" or type(list) ~= "table" then continue end
                local kept: { Entry } = {}
                for _, e in list do
                    if type(e) == "table" and type(e.text) == "string" and type(e.count) == "number" then
                        table.insert(kept, { text = e.text, count = e.count, last = if type(e.last) == "number" then e.last else 0 })
                    end
                end
                folders[folder] = kept
            end
        end
    end
end

local function order(a: Entry, b: Entry): boolean
    if a.count ~= b.count then return a.count > b.count end
    return a.last > b.last
end

local saving: any = nil
local function save()
    -- Several commands at once are one write.
    if saving then saving:stop() end
    saving = g.after(1, function()
        saving = nil
        -- What was typed is the person's own: theirs alone to read.
        file:write(g.to_json(folders, false), { mode = "600" })
    end)
end

function M.add(folder: string, text: string)
    if folder == "" or text == "" or string.sub(text, 1, 1) == " " then return end
    local list = folders[folder] or {}
    folders[folder] = list
    local now = os.time()
    for _, e in list do
        if e.text == text then
            e.count += 1
            e.last = now
            save()
            return
        end
    end
    table.insert(list, { text = text, count = 1, last = now })
    if #list > KEEP then
        table.sort(list, order)
        table.remove(list)
    end
    save()
end

-- The folder's commands, the most used first.
function M.of(folder: string): { Entry }
    local list = table.clone(folders[folder] or {})
    table.sort(list, order)
    return list
end

return M
