--!strict
-- Floema, phase 1 (docs/plan.md §7): one window, one shell. The grid is
-- Genoma's (g.pty, g.terminal, g.terminal_view); this file is the window, the
-- cursor and the keys.
--
--   genoma Floema/genoma          (FLOEMA_SHELL: the program; $SHELL otherwise)
local g = require("@genoma")
local clipboard = require("@genoma/clipboard")
local commands = require("core/commands")
local capsules = require("ui/capsules")
local look = require("ui/look")

local PAD = 12
-- Space Mono at 15 (Akusen, 2026-11-26); FLOEMA_FONT tries another, until
-- the theme file has one.
local FONT = g.env("FLOEMA_FONT") or "Space Mono"
local SIZE_DEFAULT, SIZE_MIN, SIZE_MAX = 15, 9, 32

-- What the person chose: ~/.config/floema/config.json. The size of the
-- letters is theirs to set (Akusen, 2026-11-26), and kept.
local config_file = g.file {
    path = (g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")) .. "/floema/config.json",
    watch = false,
}
local kept: { [string]: any } = {}
do
    local text = config_file.text
    if text then
        local ok, parsed = pcall(g.parse_json, text)
        if ok and type(parsed) == "table" then kept = parsed end
    end
end
local function valid_size(v: any): number?
    return if type(v) == "number" then math.clamp(math.floor(v + 0.5), SIZE_MIN, SIZE_MAX) else nil
end
local area = g.signal({ w = 980, h = 620 })
local size = g.signal(valid_size(tonumber(g.env("FLOEMA_SIZE") or "")) or valid_size(kept.font_size) or SIZE_DEFAULT)
local saving: any = nil
g.watch(function() return size.value end, function(v: number)
    if kept.font_size == v or (kept.font_size == nil and v == SIZE_DEFAULT) then return end
    kept.font_size = v
    -- Ctrl+= held is one write, not ten.
    if saving then saving:stop() end
    saving = g.after(0.5, function()
        saving = nil
        config_file:write(g.to_json(kept, true))
    end)
end)
local title = g.signal("Floema")
local focused = g.signal(true)

-- The ANSI colours: Bioma's, as its Alacritty template writes them, until
-- Bioma writes them into the theme file (plan §4).
local function palette(): { [string]: any }?
    local home = g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")
    local f = g.file { path = home .. "/alacritty/themes/bioma.toml", watch = false }
    local text = f.text
    f:stop()
    if text == nil then return nil end
    local function section(name: string): { string }?
        local body = string.match(text, "%[colors%." .. name .. "%]([^%[]*)")
        if body == nil then return nil end
        local out: { string } = {}
        for _, key in { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" } do
            local c = string.match(body, key .. "%s*=%s*'(#%x+)'")
            if c == nil then return nil end
            table.insert(out, c)
        end
        return out
    end
    local normal, bright = section("normal"), section("bright")
    if normal == nil or bright == nil then return nil end
    for _, c in bright do table.insert(normal, c) end
    return { colours = normal }
end

-- The shell: FLOEMA_SHELL, else the person's. fish marks its commands by
-- itself; bash and zsh are given Floema's marks (shell/), their own
-- configuration read first.
local program = g.env("FLOEMA_SHELL")
if program == nil or program == "" then program = g.env("SHELL") or "/bin/sh" end
local name = string.match(program, "([^/]+)$") or program
local command: { string } = { program }
local env: { [string]: string } = { TERM_PROGRAM = "Floema" }
if name == "bash" then
    command = { program, "--rcfile", g.dir .. "/shell/floema.bash" }
elseif name == "zsh" then
    env.FLOEMA_ZDOTDIR = g.env("ZDOTDIR") or ""
    env.ZDOTDIR = g.dir .. "/shell/zsh"
end

local pty = g.pty {
    command = command,
    cwd = g.env("HOME"),
    env = env,
    on_exit = function() g.quit() end,
}
local term = g.terminal {
    pty = pty,
    on_title = function(t: string) title.value = if t ~= "" then t else "Floema" end,
    on_clipboard = function(text: string) clipboard:set_text(text) end,
    on_mark = commands.mark,
}
commands.attach(term)
-- What the view leaves out follows the folds.
g.effect(function() term:hide(commands.hidden()) end)
local function colours()
    local p = palette() or {}
    p.foreground = look.text()
    p.background = look.background()
    p.cursor = look.primary()
    p.selection = look.primary()
    term:palette(p)
end
colours()
g.watch(function() return look.background() .. look.text() .. look.primary() end, colours)

-- ---- Keys --------------------------------------------------------------------------

local function paste()
    if not clipboard.available then return end
    clipboard:read("text/plain;charset=utf-8", function(text: string?)
        if text and text ~= "" then term:paste(text) end
    end)
end

local function offers_text(): boolean
    for _, t in clipboard.types do
        if string.sub(t, 1, 5) == "text/" or t == "UTF8_STRING" or t == "STRING" then return true end
    end
    return false
end

local function zoom(by: number?)
    size.value = if by == nil then SIZE_DEFAULT else math.clamp(g.untracked(function() return size.value end) + by, SIZE_MIN, SIZE_MAX)
end

-- What is done to a command: its output folded, copied, or the command
-- written at the prompt again (not run: Return runs it).
local function act(key: number, what: string)
    local c = commands.find(key)
    if c == nil then return end
    if what == "fold" then
        commands.toggle_fold(key)
    elseif what == "copy" then
        local text = commands.output_text(c)
        if text ~= "" then clipboard:set_text(text) end
    elseif what == "again" then
        commands.stood.value = nil
        term:scroll()
        term:paste(c.text)
    end
end

-- Standing on a command: Up and Down move, F folds, C copies its output,
-- R writes it again, E shows only the failed ones; Escape, or anything
-- else typed, leaves (and what was typed goes on).
local function standing(name: string, mods: any): boolean
    local stood = g.untracked(function() return commands.stood.value end)
    if mods.ctrl and not mods.alt and (name == "Up" or name == "Down") then
        commands.step(if name == "Up" then -1 else 1)
        return true
    end
    if stood == nil then return false end
    local lower = string.lower(name)
    if mods.ctrl or mods.alt then
        commands.stood.value = nil
        return false
    end
    if name == "Up" or name == "Down" then
        commands.step(if name == "Up" then -1 else 1)
    elseif lower == "f" then
        act(stood, "fold")
    elseif lower == "c" then
        act(stood, "copy")
    elseif lower == "r" then
        act(stood, "again")
    elseif lower == "e" then
        commands.failed_only.value = not g.untracked(function() return commands.failed_only.value end)
    elseif name == "Escape" then
        commands.stood.value = nil
        term:scroll()
    else
        commands.stood.value = nil
        term:scroll()
        return false
    end
    return true
end

local function key(name: string, text: string?, mods: any)
    if standing(name, mods) then return end
    local lower = string.lower(name)
    if mods.ctrl and not mods.alt then
        -- Ctrl+V pastes text; an image alone is the program's to take
        -- (Claude Code), so the key goes on.
        if lower == "v" then
            if offers_text() then
                paste()
                return
            end
        elseif lower == "c" then
            -- What is selected is copied, and the selection goes, so the
            -- next Ctrl+C interrupts; with nothing selected it interrupts.
            local text = term:selected()
            if text then
                clipboard:set_text(text)
                term:select(nil)
                return
            end
            if mods.shift then return end
        elseif name == "equal" or name == "plus" then
            zoom(1)
            return
        elseif name == "minus" then
            zoom(-1)
            return
        elseif name == "0" then
            zoom(nil)
            return
        end
    end
    -- Shift+Return: a new line for Claude Code; where the program speaks the
    -- kitty protocol it is told the key itself.
    if name == "Return" and mods.shift and not mods.ctrl and not mods.alt then
        if not term:modes().disambiguate_esc_codes then
            term:write("\27\r")
            return
        end
    end
    term:key(name, text, mods)
end

-- ---- The view ------------------------------------------------------------------------

local function view(): any
    local _ = term.changed
    return term:view()
end

-- The cursor: a block in the primary, the character under it in the
-- background's colour; hollow while the window has not the keys.
local cursor = g.capsule {
    overlay = true,
    attach = "corner",
    present = function()
        local c = term:cursor()
        local v = view()
        return c.shown and v.cell_width > 0 and term:row(c.line) ~= nil
    end,
    offset_x = function() return PAD + term:cursor().column * view().cell_width end,
    offset_y = function()
        local v = view()
        return PAD + (term:row(term:cursor().line) or 0) * v.cell_height
    end,
    width = function() return view().cell_width end,
    height = function() return view().cell_height end,
    radius = 0,
    fill = function() return if focused.value then look.primary() else look.CLEAR end,
    rim_top = look.primary,
    rim_bottom = look.primary,
    g.text {
        present = function() return focused.value end,
        text = function()
            local c = term:cursor()
            local line = term:line(c.line) or ""
            local ch = ""
            local i = 0
            for _, code in utf8.codes(line) do
                if i == c.column then
                    ch = utf8.char(code)
                    break
                end
                i += 1
            end
            return ch
        end,
        color = look.background,
        font = FONT,
        size = function() return size.value end,
    },
}

-- ---- The pointer -------------------------------------------------------------------

-- A point of the view as a cell: column, row, and whether on its right half.
local function cell_at(x: number, y: number): (number, number, boolean)
    local v = g.untracked(view)
    local cw, ch = math.max(1, v.cell_width), math.max(1, v.cell_height)
    local col = math.clamp(math.floor(x / cw), 0, math.max(0, v.cols - 1))
    local row = math.clamp(math.floor(y / ch), 0, math.max(0, v.rows - 1))
    return col, row, (x - col * cw) > cw / 2
end

local BUTTONS: { [number]: number } = { [272] = 0, [274] = 1, [273] = 2 }
-- What the press under way is: the program's, a selection, or nothing.
local holding: string? = nil
local held_button = 0
local dragged = false

local function pointer_mods(): any
    return if g.modifiers then g.modifiers() else {}
end

local function press(button: number, x: number, y: number)
    local col, row, right = cell_at(x, y)
    local b = BUTTONS[button]
    if b == nil then return end
    dragged = false
    if term:mouse("press", b, col, row, pointer_mods()) then
        holding, held_button = "program", b
        return
    end
    if b == 0 then
        holding = "select"
        term:select("char", col, row, right)
    elseif b == 1 then
        holding = nil
        paste()
    end
end

local function drag(x: number, y: number)
    local col, row, right = cell_at(x, y)
    dragged = true
    if holding == "program" then
        term:mouse("move", held_button, col, row, pointer_mods())
    elseif holding == "select" then
        term:select_to(col, row, right)
    end
end

local function release(button: number, x: number, y: number)
    local col, row = cell_at(x, y)
    if holding == "program" then
        term:mouse("release", BUTTONS[button] or held_button, col, row, pointer_mods())
    end
    holding = nil
end

local function click(button: number, x: number, y: number, count: number)
    if button ~= 272 or holding == "program" then return end
    local col, row, right = cell_at(x, y)
    if count == 2 then
        term:select("word", col, row, right)
    elseif count >= 3 then
        term:select("line", col, row, right)
    elseif not dragged then
        -- A click alone selects nothing.
        term:select(nil)
    end
end

-- Where the pointer last was, for the wheel, which is told it.
local last_at = { 0, 0 }

-- The command a row shows, for the pointer.
local function command_at(row: number): number?
    local line = term:line_at(row)
    if line == nil then return nil end
    for i = #commands.list, 1, -1 do
        local c = commands.list[i]
        local first, last = commands.span(c)
        if first and last and line >= first and line <= last then
            return if commands.ran(c) then c.key else nil
        end
    end
    return nil
end

local function moved(x: number, y: number)
    local col, row = cell_at(x, y)
    last_at = { col, row }
    capsules.hovered.value = command_at(row)
    if holding then return end
    term:mouse("move", 3, col, row, pointer_mods())
end

local function wheel(_: number, dy: number, steps: boolean): boolean
    local lines = if steps then 3 else math.max(1, math.floor(math.abs(dy) / 10))
    local up = dy < 0
    -- A program that asked for the pointer has the wheel too.
    local col, row = last_at[1], last_at[2]
    if term:mouse("wheel", if up then 64 else 65, col, row, pointer_mods()) then
        for _ = 2, lines do term:mouse("wheel", if up then 64 else 65, col, row, pointer_mods()) end
        return true
    end
    local m = term:modes()
    -- In a program of the whole screen the wheel is its arrows.
    if m.alt_screen and m.alternate_scroll and not m.mouse_report_click then
        for _ = 1, lines do term:key(if up then "Up" else "Down", nil, {}) end
    else
        term:scroll(if up then lines else -lines)
    end
    return true
end

return g.window {
    title = function() return title.value end,
    app_id = "dev.akusen.floema",
    width = 980,
    height = 620,
    min = { 320, 200 },
    g.capsule {
        grow = 1,
        radius = 0,
        blur = true,
        fill = look.background,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        align = "stretch",
        catch = true,
        on_key = key,
        on_focus = function(on: boolean)
            focused.value = on
            term:focus(on)
        end,
        on_wheel = wheel,
        on_size = function(w: number, h: number) area.value = { w = w, h = h } end,
        on_hover = function(on: boolean) if not on then capsules.hovered.value = nil end end,
        padding = PAD,
        g.terminal_view {
            terminal = term,
            grow = 1,
            cursor = "text",
            on_press = press,
            on_drag = drag,
            on_release = release,
            on_click = click,
            on_move = moved,
            font = FONT,
            size = function() return size.value end,
        },
        capsules.new {
            term = term,
            pad = PAD,
            width = function() return area.value.w - PAD * 2 end,
            act = act,
        },
        cursor,
    },
}
