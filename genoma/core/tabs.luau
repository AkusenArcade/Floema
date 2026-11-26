--!strict
-- The tabs: each one shell on a pty of its own, its terminal, its commands,
-- the folder it stands in and what it is called. A new one opens in the
-- home folder (Akusen, 2026-11-26); the last one closed closes the window.
local g = require("@genoma")
local commands = require("core/commands")
local paths = require("core/paths")

local M = {}

export type Tab = {
    id: number,
    pty: any,
    term: any,
    commands: any,
    -- Where the shell stands: OSC 7 where the shell says it, the shell's own
    -- folder at each prompt otherwise.
    cwd: any,
    -- The program the terminal is given to, when it is not the shell.
    program: any,
    title: any,
    -- Closing it was asked while something runs in it: a second time closes.
    asking: any,
}

M.tabs = g.signal({} :: { Tab })
M.tab = g.signal(nil :: Tab?)
-- Given what each terminal tells (title, clipboard), and called when the
-- last tab has gone.
M.on_title = function(_: Tab, _: string) end
M.on_clipboard = function(_: string) end
M.on_empty = function() end

-- The shell: FLOEMA_SHELL, else the person's. fish marks its commands by
-- itself; bash and zsh are given Floema's marks (shell/), their own
-- configuration read first.
local program = g.env("FLOEMA_SHELL")
if program == nil or program == "" then program = g.env("SHELL") or "/bin/sh" end
local shell = string.match(program, "([^/]+)$") or program
local function launch(): ({ string }, { [string]: string })
    local command: { string } = { program }
    local env: { [string]: string } = { TERM_PROGRAM = "Floema" }
    if shell == "bash" then
        command = { program, "--rcfile", g.dir .. "/shell/floema.bash" }
    elseif shell == "zsh" then
        env.FLOEMA_ZDOTDIR = g.env("ZDOTDIR") or ""
        env.ZDOTDIR = g.dir .. "/shell/zsh"
    end
    return command, env
end

local count = 0

-- What it is called: the program running in it, else its folder.
function M.name(t: Tab): string
    return t.program.value or paths.called(t.cwd.value)
end

-- Whether something other than the shell runs in it.
function M.busy(t: Tab): boolean
    return g.untracked(function() return t.program.value end) ~= nil
end

local function remove(t: Tab)
    local list = table.clone(g.untracked(function() return M.tabs.value end))
    local at = table.find(list, t)
    if at == nil then return end
    table.remove(list, at)
    if g.untracked(function() return M.tab.value end) == t then
        M.tab.value = list[math.min(at, #list)]
    end
    M.tabs.value = list
    if #list == 0 then M.on_empty() end
end

function M.new(folder: string?): Tab
    count += 1
    local here = folder or paths.home
    local command, env = launch()
    local t: any = {
        id = count,
        cwd = g.signal(here),
        program = g.signal(nil :: string?),
        title = g.signal(""),
        asking = g.signal(false),
    }
    -- What runs in it, read when the shell says a command starts or ends and
    -- when the title changes (a program without the shell's marks).
    local reading: any = nil
    local function read()
        local f = t.pty:foreground()
        local name = f and f.name
        t.program.value = if name and name ~= "" and name ~= shell then name else nil
        if t.program.value == nil then t.asking.value = false end
    end
    local function soon()
        if reading then reading:stop() end
        reading = g.after(0.15, function()
            reading = nil
            read()
        end)
    end
    t.pty = g.pty {
        command = command,
        cwd = here,
        env = env,
        on_exit = function()
            if reading then reading:stop() end
            remove(t)
        end,
    }
    t.term = g.terminal {
        pty = t.pty,
        on_title = function(text: string)
            t.title.value = text
            M.on_title(t, text)
            soon()
        end,
        on_clipboard = function(text: string) M.on_clipboard(text) end,
        on_mark = function(kind: string, id: number, line: number, column: number, code: number?)
            t.commands.mark(kind, id, line, column, code)
            if kind == "prompt" then
                local cwd = t.pty:cwd()
                if cwd then t.cwd.value = cwd end
            end
            if kind == "output" then
                soon()
            elseif kind == "prompt" or kind == "done" then
                read()
            end
        end,
        on_cwd = function(path: string) if path ~= "" then t.cwd.value = path end end,
    }
    t.commands = commands.new(t.term)
    -- What the view leaves out follows the folds.
    g.effect(function() t.term:hide(t.commands.hidden()) end)
    local list = table.clone(g.untracked(function() return M.tabs.value end))
    local current = g.untracked(function() return M.tab.value end)
    -- Beside the one seen.
    local at = (current and table.find(list, current) or #list) + 1
    table.insert(list, at, t)
    M.tabs.value = list
    M.tab.value = t
    return t
end

function M.show(t: Tab)
    if table.find(g.untracked(function() return M.tabs.value end), t) then M.tab.value = t end
end

local forgetting: { [any]: any } = {}

-- `force`, or nothing running in it: it closes. Otherwise it asks first, and
-- forgets having asked after a while.
function M.close(t: Tab, force: boolean?)
    if not force and M.busy(t) and not g.untracked(function() return t.asking.value end) then
        t.asking.value = true
        if forgetting[t] then forgetting[t]:stop() end
        forgetting[t] = g.after(4, function()
            forgetting[t] = nil
            t.asking.value = false
        end)
        return
    end
    if forgetting[t] then forgetting[t]:stop() end
    forgetting[t] = nil
    t.asking.value = false
    t.pty:stop()
    remove(t)
end

function M.move(t: Tab, to: number)
    local list = table.clone(g.untracked(function() return M.tabs.value end))
    local at = table.find(list, t)
    if at == nil then return end
    table.remove(list, at)
    table.insert(list, math.clamp(to, 1, #list + 1), t)
    M.tabs.value = list
end

-- The one beside the one seen: `by` -1 left, 1 right, round.
function M.step(by: number)
    local list = g.untracked(function() return M.tabs.value end)
    if #list < 2 then return end
    local at = table.find(list, g.untracked(function() return M.tab.value end)) or 1
    M.tab.value = list[(at - 1 + by) % #list + 1]
end

function M.any(): boolean return #M.tabs.value > 1 end

return M
