--!strict
-- What makes sense where the shell stands (docs/plan.md §6), read when the
-- panel opens: the project's own commands (Makefile, package.json, just,
-- cargo, makepkg, the folder's executables), git as it is now, and the
-- commands already run in this folder (core/history).
local g = require("@genoma")
local history = require("core/history")

local M = {}

export type Item = {
    -- What is written at the prompt.
    text: string,
    -- Said beside it, quietly: where it comes from, how much, how often.
    meta: string?,
}
export type Group = { key: string, title: string, items: { Item } }

-- What the folder holds, the file's text or nil.
local function read(folder: string, name: string): string?
    local f = g.file { path = folder .. "/" .. name, watch = false }
    local text = f.text
    f:stop()
    return text
end

local function first_of(folder: string, names: { string }): string?
    for _, n in names do
        local text = read(folder, n)
        if text then return text end
    end
    return nil
end

local function add(out: { Item }, seen: { [string]: boolean }, text: string, meta: string?)
    if seen[text] then return end
    seen[text] = true
    table.insert(out, { text = text, meta = meta })
end

-- Make's targets written plainly: not the special ones (.PHONY), not
-- patterns, not variables (`a := b`, `a ::= b`).
local function make_targets(text: string): { string }
    local out: { string } = {}
    for line in string.gmatch(text, "[^\n]+") do
        local name, after = string.match(line, "^([%w_][%w_%-%./]*)%s*:(.?)")
        if name and after ~= "=" and after ~= ":" then table.insert(out, name) end
    end
    return out
end

-- just's recipes: a name at the start of a line, its parameters, a colon;
-- not its settings, aliases or assignments.
local JUST_WORDS = { set = true, alias = true, export = true, import = true, mod = true, unexport = true }
local function just_recipes(text: string): { string }
    local out: { string } = {}
    for line in string.gmatch(text, "[^\n]+") do
        -- (Parameters may have defaults, `a='x'`; an assignment is `name :=`.)
        local name, after = string.match(line, "^@?([%a_][%w_%-]*)[^:]*:(.?)")
        if name and after ~= "=" and not JUST_WORDS[name] then table.insert(out, name) end
    end
    return out
end

local function project(folder: string, executables: { string }, main: boolean): { Item }
    local out: { Item } = {}
    local seen: { [string]: boolean } = {}
    local makefile = first_of(folder, { "GNUmakefile", "makefile", "Makefile" })
    if makefile then
        for _, t in make_targets(makefile) do add(out, seen, "make " .. t, "make") end
    end
    local package = read(folder, "package.json")
    if package then
        local ok, parsed = pcall(g.parse_json, package)
        if ok and type(parsed) == "table" and type(parsed.scripts) == "table" then
            -- The runner the folder's lock file says.
            local runner = "npm run"
            if read(folder, "bun.lock") or read(folder, "bun.lockb") then
                runner = "bun run"
            elseif read(folder, "pnpm-lock.yaml") then
                runner = "pnpm run"
            elseif read(folder, "yarn.lock") then
                runner = "yarn"
            end
            local names: { string } = {}
            for name in parsed.scripts do
                if type(name) == "string" then table.insert(names, name) end
            end
            table.sort(names)
            for _, name in names do add(out, seen, runner .. " " .. name, string.match(runner, "^%S+")) end
        end
    end
    local justfile = first_of(folder, { "justfile", "Justfile", ".justfile" })
    if justfile then
        for _, r in just_recipes(justfile) do add(out, seen, "just " .. r, "just") end
    end
    local cargo = read(folder, "Cargo.toml")
    if cargo then
        add(out, seen, "cargo build", "cargo")
        add(out, seen, "cargo test", "cargo")
        if main or string.find(cargo, "[[bin]]", 1, true) then add(out, seen, "cargo run", "cargo") end
    end
    if read(folder, "PKGBUILD") then add(out, seen, "makepkg -si", "makepkg") end
    for _, name in executables do add(out, seen, "./" .. name, "here") end
    return out
end

-- git as it is now, from `git status --porcelain=v2 --branch`.
local function git(lines: { string }): (string?, { Item })
    local branch: string? = nil
    local ahead, behind, tracked, untracked = 0, 0, 0, 0
    for _, l in lines do
        local head = string.match(l, "^# branch%.head (.+)$")
        if head then branch = head end
        local a, b = string.match(l, "^# branch%.ab %+(%d+) %-(%d+)$")
        if a and b then
            ahead, behind = tonumber(a) or 0, tonumber(b) or 0
        end
        local kind = string.sub(l, 1, 2)
        if kind == "1 " or kind == "2 " or kind == "u " then
            tracked += 1
        elseif kind == "? " then
            untracked += 1
        end
    end
    local out: { Item } = {}
    if branch == nil then return nil, out end
    local changed = tracked + untracked
    if changed > 0 then
        local text = if untracked > 0 then "git add -A && git commit" else "git commit -a"
        table.insert(out, { text = text, meta = `{changed} changed` })
    end
    if ahead > 0 then table.insert(out, { text = "git push", meta = `{ahead} ahead` }) end
    if behind > 0 then table.insert(out, { text = "git pull", meta = `{behind} behind` }) end
    if #out == 0 then table.insert(out, { text = "git status", meta = "clean" }) end
    return branch, out
end

-- How many of the folder's own commands are offered before anything is
-- typed; typing reaches all of them.
local RECENT = 8

-- The folder's commands: `give(groups)` at once with what the project's
-- files say, and again when git and the executables have come back.
function M.read(folder: string, give: ({ Group }) -> ())
    local executables: { string } = {}
    local main = false
    local status: { string } = {}
    local function build(done: boolean)
        local out: { Group } = {}
        local p = project(folder, executables, main)
        if #p > 0 then table.insert(out, { key = "project", title = "Project", items = p }) end
        local branch, items = git(status)
        if done and branch then table.insert(out, { key = "git", title = `git · {branch}`, items = items }) end
        local ran: { Item } = {}
        for _, e in history.of(folder) do
            table.insert(ran, { text = e.text, meta = if e.count > 1 then `×{e.count}` else nil })
        end
        if #ran > 0 then table.insert(out, { key = "history", title = "Run here", items = ran }) end
        give(out)
    end
    build(false)
    -- One look at the folder, its name given as an argument, never in the
    -- script: the executables at its top, whether cargo has something to
    -- run, and git.
    local SCRIPT = [[
cd -- "$1" || exit 0
for f in *; do [ -f "$f" ] && [ -x "$f" ] && printf 'x %s\n' "$f"; done
[ -f src/main.rs ] && echo main
git status --porcelain=v2 --branch 2>/dev/null | sed 's/^/g /'
]]
    pcall(function()
        g.process {
            command = { "sh", "-c", SCRIPT, "sh", folder },
            on_line = function(line: string)
                local kind, rest = string.sub(line, 1, 2), string.sub(line, 3)
                if kind == "x " then
                    if #executables < 8 then table.insert(executables, rest) end
                elseif kind == "g " then
                    table.insert(status, rest)
                elseif line == "main" then
                    main = true
                end
            end,
            on_exit = function() build(true) end,
        }
    end)
end

M.RECENT = RECENT

return M
