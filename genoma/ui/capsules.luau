--!strict
-- The commands drawn over the grid, discreetly: a thread down the margin
-- beside each one's lines, in the alert colour when it failed and the
-- primary while it runs; how it ended and how long it took on its line, only
-- when there is something to say. Under the pointer, or stood on, it shows
-- its outline and what can be done with it.
local g = require("@genoma")
local look = require("ui/look")

local M = {}

local RATE_THREAD = g.dir .. "/ui/rate_thread.wgsl"

local function push(out: { number }, hex: string)
    local c = g.colour.parse(hex)
    if c == nil then return end
    table.insert(out, c.r)
    table.insert(out, c.g)
    table.insert(out, c.b)
    table.insert(out, c.a)
end

local ACTION_H = 24

type Shown = {
    key: number,
    top: number,
    bottom: number,
    -- The row of its command's line, when in view.
    line_row: number?,
    state: string,
    code: number?,
    took: string,
    folded: number,
    -- What it said of its progress, while it runs.
    progress: { state: number, value: number }?,
}

local function label(text: () -> string, colour: () -> string): any
    return g.text {
        text = function() return string.upper(text()) end,
        color = colour,
        font = look.technical,
        size = 10,
        weight = 600,
        tracking = 0.08,
    }
end

-- `t`: term, commands (core/commands), pad (the grid's corner from the
-- window's), width() of the grid, act(key, what) for "fold", "copy", "again",
-- rate() (how fast the program writes, bytes a second).
function M.new(t: { [string]: any }): any
    local term = t.term
    local commands = t.commands
    -- The running command's dashes: units a second, on a logarithmic scale
    -- of the bytes (a few a second to many megabytes), 0 when none come.
    local function speed(): number
        local r = if t.rate then t.rate() else 0
        if r < 8 then return 0 end
        return 10 + 34 * math.log10(1 + r / 1024)
    end
    local PAD = t.pad
    local shown = g.computed(function(): { Shown }
        local _ = term.changed
        local _v = commands.version.value
        local folded = commands.folded.value
        local out: { Shown } = {}
        -- A program that took the whole screen (vim, the alternate screen) is
        -- the window: nothing is drawn over it.
        if term:modes().alt_screen then return out end
        for i, c in commands.list do
            local first, last = commands.span(c)
            -- Only what is in view is asked whether its line still says it.
            local seen = first ~= nil and last ~= nil and term:span(first, last) ~= nil
            -- One whose line was drawn over is gone, running or not: a program
            -- that draws over the shell's lines (Claude Code) has the whole
            -- window, and a thread beside it would tell nothing it does not
            -- (Akusen, 2026-11-27).
            if seen and (commands.ran(c) or i == #commands.list and c.output) and commands.intact(c) then
                if first and last then
                    local top, bottom = term:span(first, last)
                    if top and bottom then
                        local line = commands.line(c.command)
                        local of, ot = commands.output_span(c)
                        table.insert(out, {
                            key = c.key,
                            top = top,
                            bottom = bottom,
                            line_row = if line then term:row(line) else nil,
                            state = if c.done == nil then "running" elseif c.code ~= 0 then "failed" else "done",
                            code = c.code,
                            took = commands.took(c),
                            folded = if folded[c.key] and of and ot then ot - of + 1 else 0,
                            progress = if c.done == nil then c.progress else nil,
                        })
                    end
                end
            end
        end
        return out
    end)
    local function view(): any
        local _ = term.changed
        return term:view()
    end
    local function capsule(item: () -> Shown): any
        local key = g.untracked(item).key
        -- Lit under the pointer or stood on, once it has ended: what can be
        -- done with it is for a command that is done.
        local function lit(): boolean
            if item().state == "running" then return false end
            return commands.stood.value == key or commands.hovered.value == key
        end
        local function y(row: number): number return PAD + row * view().cell_height end
        local function h(): number return (item().bottom - item().top + 1) * view().cell_height end
        local function thread(): string
            local s = item().state
            if s == "failed" then return look.alert() end
            if s == "running" then return look.primary() end
            return if lit() then look.node() else g.colour.alpha(look.line(), 0.7)
        end
        local function meta_row(): number? return item().line_row end
        -- How much of `full` the progress fills.
        local function level(full: number): number
            local p = item().progress
            if p == nil then return 0 end
            return math.max(2, full * math.clamp(p.value, 0, 100) / 100)
        end
        local function action(name: string, what: string, word: () -> string): any
            local over = g.signal(false)
            return g.capsule {
                role = "button",
                name = name,
                height = ACTION_H,
                padding_x = 10,
                radius = look.round(ACTION_H / 2),
                align = "center",
                justify = "center",
                fill = function() return if over.value then look.chosen() else look.glass_over() end,
                rim_top = function() return if over.value then look.primary() else look.node() end,
                rim_bottom = function() return if over.value then look.primary() else look.node() end,
                transition = { fill = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change" },
                on_hover = function(on: boolean) over.value = on end,
                on_press = function() end,
                on_click = function(button: number) if button == 272 then t.act(key, what) end end,
                label(word, look.text),
            }
        end
        return g.box {
            overlay = true,
            attach = "corner",
            width = function() return t.width() + PAD * 2 end,
            -- The outline, under the pointer or stood on.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = lit,
                offset_x = PAD - 7,
                offset_y = function() return y(item().top) - 3 end,
                width = function() return t.width() + 14 end,
                height = function() return h() + 6 end,
                radius = look.round(10),
                fill = function() return g.colour.alpha(look.text(), 0.025) end,
                rim_top = function() return if commands.stood.value == key then look.primary() else look.node() end,
                rim_bottom = function() return if commands.stood.value == key then look.primary() else look.node() end,
                transition = { rim_top = "ui_change", rim_bottom = "ui_change" },
            },
            -- The thread down the margin; pressed, the output folds.
            g.box {
                overlay = true,
                attach = "corner",
                role = "button",
                name = "Fold",
                offset_x = 0,
                offset_y = function() return y(item().top) end,
                width = PAD - 2,
                height = h,
                cursor = "pointer",
                on_hover = function(on: boolean) if on then commands.hovered.value = key end end,
                on_press = function() end,
                on_click = function(button: number) if button == 272 then t.act(key, "fold") end end,
                g.capsule {
                    overlay = true,
                    attach = "corner",
                    present = function() return item().state ~= "running" end,
                    offset_x = 4,
                    offset_y = 2,
                    width = 2,
                    height = function() return math.max(2, h() - 4) end,
                    radius = 1,
                    fill = thread,
                    rim_top = look.CLEAR,
                    rim_bottom = look.CLEAR,
                    transition = { fill = "ui_change" },
                },
                -- What it said of its progress: a level rising from the
                -- foot of the thread, in the alert colour on an error, the
                -- secondary while it is paused.
                g.capsule {
                    overlay = true,
                    attach = "corner",
                    present = function()
                        local p = item().progress
                        return p ~= nil and p.state ~= 3
                    end,
                    offset_x = 4,
                    offset_y = function()
                        local full = math.max(2, h() - 4)
                        return 2 + full - level(full)
                    end,
                    width = 2,
                    height = function() return level(math.max(2, h() - 4)) end,
                    radius = 1,
                    fill = function()
                        local p = item().progress
                        if p and p.state == 2 then return look.alert() end
                        if p and p.state == 4 then return look.secondary() end
                        return look.primary()
                    end,
                    rim_top = look.CLEAR,
                    rim_bottom = look.CLEAR,
                    transition = { offset_y = "ui_change", height = "ui_change", fill = "ui_change" },
                },
                -- Running, Bioma's rate thread: dashes run down it as fast
                -- as the program writes, still when it writes nothing.
                g.shader {
                    overlay = true,
                    attach = "corner",
                    present = function() return item().state == "running" end,
                    offset_x = 2,
                    offset_y = 2,
                    width = 6,
                    height = function() return math.max(2, h() - 4) end,
                    src = RATE_THREAD,
                    follow = 0,
                    clock = function() return speed() > 0 end,
                    values = function()
                        local out = { speed(), 2, look.thread, 0 }
                        push(out, g.colour.alpha(look.primary(), 0.35))
                        push(out, look.primary())
                        return out
                    end,
                },
            },
            -- Stood on or under the pointer, what can be done: in the middle
            -- of the command's line (Akusen, 2026-11-26).
            g.box {
                overlay = true,
                attach = "corner",
                present = function() return meta_row() ~= nil and lit() end,
                offset_x = PAD,
                offset_y = function()
                    local r = meta_row() or 0
                    return y(r) + (view().cell_height - ACTION_H) / 2
                end,
                width = t.width,
                height = ACTION_H,
                direction = "row",
                align = "center",
                justify = "center",
                gap = 6,
                action("Fold", "fold", function() return if item().folded > 0 then "Unfold" else "Fold" end),
                action("Copy the output", "copy", function() return "Copy" end),
                action("Again", "again", function() return "Again" end),
            },
            -- What there is to say, at the end of the command's line: how it
            -- ended, how long it took, how much is folded.
            g.box {
                overlay = true,
                attach = "corner",
                present = function() return meta_row() ~= nil end,
                offset_x = function() return PAD + t.width() - 320 end,
                offset_y = function()
                    local r = meta_row() or 0
                    return y(r) + (view().cell_height - ACTION_H) / 2
                end,
                width = 320,
                height = ACTION_H,
                direction = "row",
                align = "center",
                justify = "end",
                g.capsule {
                    present = function()
                        local s = item()
                        return s.folded > 0 or s.took ~= "" or (s.code ~= nil and s.code ~= 0)
                    end,
                    height = ACTION_H,
                    padding_x = 10,
                    radius = look.round(ACTION_H / 2),
                    direction = "row",
                    align = "center",
                    gap = 10,
                    fill = look.glass_over,
                    rim_top = look.CLEAR,
                    rim_bottom = look.CLEAR,
                    g.box {
                        present = function() return item().folded > 0 end,
                        label(function() return `{item().folded} lines` end, look.text_muted),
                    },
                    g.box {
                        present = function() return item().took ~= "" end,
                        label(function() return item().took end, look.text_faint),
                    },
                    g.box {
                        present = function() return item().code ~= nil and item().code ~= 0 end,
                        label(function() return `exit {item().code}` end, look.alert),
                    },
                },
            },
        }
    end
    return g.each {
        overlay = true,
        attach = "corner",
        items = function() return shown.value end,
        key = function(s: Shown) return s.key end,
        row = capsule,
    }
end

return M
