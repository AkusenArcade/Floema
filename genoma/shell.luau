--!strict
-- Floema (docs/plan.md): the window, its tabs, each tab's grid, cursor and
-- keys. The grid is Genoma's (g.pty, g.terminal, g.terminal_view); the
-- shells are core/tabs's.
--
--   genoma Floema/genoma   (FLOEMA_SHELL: the program, $SHELL otherwise;
--                           FLOEMA_CWD: the first tab's folder, home otherwise)
local g = require("@genoma")
local clipboard = require("@genoma/clipboard")
local tabs = require("core/tabs")
local capsules = require("ui/capsules")
local cursor_ui = require("ui/cursor")
local look = require("ui/look")
local tab_row = require("ui/tabs")

local PAD = 12
local E, GAP = look.margin_edge, look.gap
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

-- Each terminal is given the colours, and again when the palette changes.
local function colours(term: any)
    local p = palette() or {}
    p.foreground = look.text()
    p.background = look.background()
    p.cursor = look.primary()
    p.selection = look.primary()
    term:palette(p)
end
g.watch(function() return look.background() .. look.text() .. look.primary() end, function()
    for _, t in g.untracked(function() return tabs.tabs.value end) do colours(t.term) end
end)

tabs.on_clipboard = function(text: string) clipboard:set_text(text) end

-- Notifications, Bioma's (as its own: notify-send), only when they tell
-- something not seen: the window without the keys, or another tab.
local function unseen(t: tabs.Tab): boolean
    return not g.untracked(function() return focused.value end) or g.untracked(seen) ~= t
end
local function notify(title: string, body: string, urgent: boolean?)
    local command = { "notify-send", "-a", "Floema", "-i", "utilities-terminal" }
    if urgent then
        table.insert(command, "-u")
        table.insert(command, "critical")
    end
    table.insert(command, title)
    if body ~= "" then table.insert(command, body) end
    pcall(function() g.process { command = command } end)
end
-- A command that took long and ended where it was not seen.
local LONG = 10
tabs.on_finished = function(t: tabs.Tab, c: any, took: number)
    if took < LONG or not unseen(t) then return end
    local failed = c.code ~= nil and c.code ~= 0
    notify(if failed then `Failed, exit {c.code}` else "Done", c.text, false)
end
tabs.on_notify = function(t: tabs.Tab, title: string, body: string)
    if not unseen(t) then return end
    notify(if title ~= "" then title else tabs.name(t), body)
end
-- The bell rings at the cursor of its tab.
local bells: { [number]: any } = {}
local function bells_of(t: tabs.Tab): any
    if bells[t.id] == nil then bells[t.id] = g.signal(0) end
    return bells[t.id]
end
tabs.on_bell = function(t: tabs.Tab)
    local b = bells_of(t)
    b.value = g.untracked(function() return b.value end) + 1
end
tabs.on_empty = function() g.quit() end

local function seen(): tabs.Tab? return tabs.tab.value end
local title = g.computed(function(): string
    local t = seen()
    local text = if t then t.title.value else ""
    return if text ~= "" then text else "Floema"
end)

-- The keys a tab gives its terminal, and its wheel: set as each is built.
type Hands = { key: (string, string?, any) -> (), wheel: (number, number, boolean) -> boolean }
local hands: { [number]: Hands } = {}

-- Only the tab seen has the keys.
g.effect(function()
    local on = focused.value
    local current = seen()
    for _, t in tabs.tabs.value do t.term:focus(on and t == current) end
end)

-- ---- A tab's grid ------------------------------------------------------------------

local function screen(tab: tabs.Tab): any
    local term = tab.term
    local commands = tab.commands
    colours(term)

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

    local cursor = cursor_ui.new {
        term = term,
        pad = PAD,
        view = view,
        focused = function() return focused.value end,
        font = FONT,
        size = function() return size.value end,
        bells = function() return bells_of(tab).value end,
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
        commands.hovered.value = command_at(row)
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

    hands[tab.id] = { key = key, wheel = wheel }
    return g.box {
        grow = 1,
        align = "stretch",
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
            commands = commands,
            pad = PAD,
            width = function() return area.value.w - PAD * 2 end,
            act = act,
            rate = function() return tab.rate.value end,
        },
        cursor,
    }
end

-- ---- The window's own keys -------------------------------------------------------------

-- Ctrl+Shift+T and Ctrl+Shift+W: Ctrl+W deletes a word in the shell, Ctrl+T
-- is fish's file search. Ctrl+Tab and Ctrl+PgUp/PgDn move; with Shift,
-- PgUp/PgDn move the tab itself.
local function window_key(name: string, text: string?, mods: any)
    local lower = string.lower(name)
    local t = g.untracked(seen)
    if mods.ctrl and not mods.alt then
        if mods.shift and lower == "t" then
            tabs.new()
            return
        elseif mods.shift and lower == "w" then
            if t then tabs.close(t) end
            return
        elseif name == "Tab" or name == "ISO_Left_Tab" then
            tabs.step(if mods.shift or name == "ISO_Left_Tab" then -1 else 1)
            return
        elseif name == "Prior" or name == "Page_Up" or name == "Next" or name == "Page_Down" then
            local by = if name == "Prior" or name == "Page_Up" then -1 else 1
            if mods.shift then
                if t then
                    local at = table.find(g.untracked(function() return tabs.tabs.value end), t)
                    if at then tabs.move(t, at + by) end
                end
            else
                tabs.step(by)
            end
            return
        end
    end
    if t and name == "Escape" and g.untracked(function() return t.asking.value end) then
        t.asking.value = false
        return
    end
    local h = if t then hands[t.id] else nil
    if h then h.key(name, text, mods) end
end

local function window_wheel(dx: number, dy: number, steps: boolean): boolean
    local t = g.untracked(seen)
    local h = if t then hands[t.id] else nil
    return if h then h.wheel(dx, dy, steps) else false
end

local first_folder = g.env("FLOEMA_CWD")
tabs.new(if first_folder and first_folder ~= "" then first_folder else nil)

-- Above the grid: the tabs, always, the one seen named by what runs in it
-- or its folder. (The folder's path as capsules, ui/thread.luau, is left
-- out for now: Akusen, 2026-11-26.)
local header = g.box {
    direction = "column",
    align = "stretch",
    padding_x = E,
    g.box { height = E },
    tab_row.new(function() return area.value.w - E * 2 end),
    g.box { height = GAP - 4 },
}

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
        direction = "column",
        align = "stretch",
        catch = true,
        on_key = window_key,
        on_focus = function(on: boolean) focused.value = on end,
        on_wheel = window_wheel,
        on_size = function(w: number, h: number) area.value = { w = w, h = h } end,
        on_hover = function(on: boolean)
            local t = g.untracked(seen)
            if not on and t then t.commands.hovered.value = nil end
        end,
        header,
        g.each {
            grow = 1,
            direction = "column",
            align = "stretch",
            -- Only the seen tab's grid is built: its terminal goes on without it.
            items = function(): { tabs.Tab }
                local t = seen()
                return if t then { t } else {}
            end,
            key = function(t: tabs.Tab) return t.id end,
            row = function(item: () -> tabs.Tab, _: any) return screen(g.untracked(item)) end,
        },
    },
}
