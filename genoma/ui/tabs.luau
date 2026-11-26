--!strict
-- The tabs, as Akusen drew them (2026-11-26): their names in a row, Bioma's
-- segmented control at the size of a name, on a track or bare (TRACK); the
-- one seen is a pill in the secondary (the primary is the interactive
-- components'). Choosing another, the pill goes to it
-- as a drop would: its leading edge first, quick and a little past, the
-- trailing one after it, softer (`pill_lead`, `pill_trail`), so it
-- stretches on the way and gathers again where it arrives. A name is
-- written dark while the pill is under it. Closing one where something
-- runs asks first: its name says so in the alert colour, and a second close
-- closes it.
local g = require("@genoma")
local tabs = require("core/tabs")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

-- With a track under the names (true), or the names bare (false).
local TRACK = true
local H, INSET, PAD, CLOSE, NAME_MAX, GAP = look.action_height, 3, 18, 16, 180, 2
M.HEIGHT = H + INSET * 2

local function said(t: tabs.Tab): string
    return if t.asking.value then `{t.program.value or "it"} runs: close?` else tabs.name(t)
end

local function name_w(text: string, room: number): number
    local w = g.text_width { text = text, font = look.expressive(), size = look.font_label, weight = 600 }
    return math.min(math.ceil(w) + 1, room)
end

-- A closed one is there until it has gone back.
type Shown = { tab: tabs.Tab, leaving: boolean, fresh: boolean }
local shown = g.signal({} :: { Shown })
local going: any = nil
g.watch(function() return tabs.tabs.value end, function(list: { tabs.Tab })
    local before = g.untracked(function() return shown.value end)
    local after: { Shown } = {}
    local had: { [any]: boolean } = {}
    for _, s in before do if not s.leaving then had[s.tab] = true end end
    for _, t in list do table.insert(after, { tab = t, leaving = false, fresh = #before > 0 and not had[t] }) end
    for i, s in before do
        if table.find(list, s.tab) == nil and not s.leaving and #list > 1 then
            table.insert(after, math.min(i, #after + 1), { tab = s.tab, leaving = true, fresh = false })
        end
    end
    shown.value = after
    if going then going:stop() end
    going = g.after(look.CLOSE + 0.02, function()
        going = nil
        local kept: { Shown } = {}
        for _, s in g.untracked(function() return shown.value end) do
            if not s.leaving then table.insert(kept, s) end
        end
        shown.value = kept
    end)
end)

-- `width()`: the room the row has.
function M.new(width: () -> number): any
    -- What a name may take, when they do not all fit.
    local function room(): number
        local n = #tabs.tabs.value
        local free = width() - INSET * 2 - H - 8 - GAP * n - n * (PAD * 2 + CLOSE)
        return math.clamp(math.floor(free / math.max(1, n)), 24, NAME_MAX)
    end
    -- A name and the room for its cross, padded alike either side.
    local function slot_w(t: tabs.Tab): number
        return PAD * 2 + CLOSE + name_w(said(t), room())
    end
    -- Where the seen one is, from the widths the names are going to.
    local function place(): (number, number)
        local x = 0
        local seen = tabs.tab.value
        for _, s in shown.value do
            if not s.leaving then
                local w = slot_w(s.tab)
                if s.tab == seen then return x, x + w end
                x += w + GAP
            end
        end
        return 0, 0
    end
    local function names_w(): number
        local x, n = 0, 0
        for _, s in shown.value do
            if not s.leaving then
                x += slot_w(s.tab) + (if n > 0 then GAP else 0)
                n += 1
            end
        end
        return x
    end

    -- The pill's two edges, each on its own spring: the one it moves
    -- towards leads.
    local function edges(): { number }
        local l, r = place()
        return { l, r }
    end
    local first = g.untracked(edges)
    local left, right = g.animated(first[1]), g.animated(first[2])
    g.watch(function()
        local l, r = place()
        return `{l}:{r}`
    end, function()
        local e = g.untracked(edges)
        local l, r = e[1], e[2]
        local going_right = l > g.untracked(function() return left.target end)
        left:set(l, if going_right then "pill_trail" else "pill_lead")
        right:set(r, if going_right then "pill_lead" else "pill_trail")
    end)

    local held: any = nil
    local function slot(item: () -> Shown, _: any): any
        local first = g.untracked(item)
        local function tab(): tabs.Tab return item().tab end
        local grown = g.signal(not first.fresh)
        if first.fresh then g.after(0, function() grown.value = true end) end
        local over = g.signal(false)
        local function seen(): boolean return tabs.tab.value == tab() end
        local function out(): boolean return grown.value and not item().leaving end
        local function timing(): string return if out() then "cell_open" else "cell_close" end
        local function asking(): boolean return tab().asking.value end
        local last = 0
        local function wide(): number
            -- Going, it is no longer asked what it holds.
            if not item().leaving then last = slot_w(tab()) end
            return last
        end
        local function width_of(t: tabs.Tab): number return g.untracked(function() return slot_w(t) end) end
        -- Whether the pill is under the name's middle now.
        local function covered(): boolean
            local x = 0
            for _, s in shown.value do
                if s.tab == tab() then break end
                if not s.leaving then x += slot_w(s.tab) + GAP end
            end
            local middle = x + wide() / 2
            return middle >= left.value and middle <= right.value
        end
        local function ink(): string
            if covered() then return look.background() end
            if asking() then return look.alert() end
            return if over.value then look.text() else look.text_muted()
        end
        return g.box {
            role = "button",
            name = "Tab",
            width = function() return if out() then wide() else 0 end,
            height = H,
            clip = true,
            opacity = function() return if out() then 1 else 0 end,
            transition = { width = timing, opacity = timing },
            on_hover = function(on: boolean) over.value = on end,
            on_press = function(button: number)
                if button == 272 then
                    local t = g.untracked(tab)
                    tabs.show(t)
                    held = { tab = t }
                end
            end,
            -- Dragged past the middle of the one beside it, it takes its place.
            on_drag = function(x: number)
                if held == nil then return end
                local list = g.untracked(function() return tabs.tabs.value end)
                local at = table.find(list, held.tab)
                if at == nil then return end
                local w = width_of(held.tab)
                local next_one, before = list[at + 1], list[at - 1]
                if next_one and x > w + GAP + width_of(next_one) / 2 then
                    tabs.move(held.tab, at + 1)
                elseif before and x < -GAP - width_of(before) / 2 then
                    tabs.move(held.tab, at - 1)
                end
            end,
            on_release = function() held = nil end,
            on_click = function(button: number)
                if button == 274 then tabs.close(g.untracked(tab)) end
            end,
            -- The name in the middle; the cross in the room on its right.
            g.box {
                overlay = true,
                attach = "corner",
                width = wide,
                height = H,
                direction = "row",
                align = "center",
                justify = "center",
                g.text {
                    text = function() return said(tab()) end,
                    max_width = room,
                    ellipsize = "middle",
                    -- At once: the pill passing is what changes it.
                    color = ink,
                    font = look.expressive,
                    size = look.font_label,
                    weight = function() return if seen() then 600 else 500 end,
                },
            },
            g.box {
                overlay = true,
                attach = "corner",
                role = "button",
                name = "Close the tab",
                offset_x = function() return wide() - PAD / 2 - CLOSE end,
                width = CLOSE,
                height = H,
                align = "center",
                justify = "center",
                opacity = function() return if over.value or asking() then 1 else 0 end,
                transition = { opacity = "ui_change" },
                on_hover = function(on: boolean) over.value = on end,
                on_press = function() end,
                on_click = function(button: number) if button == 272 then tabs.close(g.untracked(tab)) end end,
                ui.glyph("close", 10, function() return false end, ink),
            },
        }
    end

    local function seen_asking(): boolean
        local t = tabs.tab.value
        return t ~= nil and t.asking.value
    end
    local function edge(): string
        local h, sat, l = g.colour.hsl(if seen_asking() then look.alert() else look.secondary())
        return g.colour.hsla(math.max(0, h), sat * 0.6, l * 0.42, 1)
    end
    local track = g.capsule {
        width = function() return names_w() + INSET * 2 end,
        height = H + INSET * 2,
        radius = look.round((H + INSET * 2) / 2),
        -- A well a little darker than the window, with no outline: an
        -- outline would make it Bioma's segmented choice (Akusen).
        fill = function() return if TRACK then g.colour.alpha("#000000", 0.28) else look.CLEAR end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        transition = { width = "cell_open" },
        -- The pill under the seen one's name.
        g.capsule {
            overlay = true,
            attach = "corner",
            -- Kept inside the track, however far a spring carries an edge.
            offset_x = function() return INSET + math.clamp(left.value, 0, names_w() - H) end,
            offset_y = INSET,
            width = function()
                local l = math.clamp(left.value, 0, names_w() - H)
                return math.max(H, math.min(right.value, names_w()) - l)
            end,
            height = H,
            radius = look.round(H / 2),
            fill = function() return if seen_asking() then look.alert() else look.secondary_top() end,
            fill_bottom = function() return if seen_asking() then look.alert() else look.secondary_bottom() end,
            -- Its edge in its own hue, darker (Akusen's mockup).
            rim_top = edge,
            rim_bottom = edge,
            transition = { fill = "ui_change", fill_bottom = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change" },
        },
        g.each {
            overlay = true,
            attach = "corner",
            offset_x = INSET,
            offset_y = INSET,
            direction = "row",
            gap = GAP,
            items = function() return shown.value end,
            key = function(s: Shown) return s.tab.id end,
            row = slot,
        },
    }
    return g.box {
        direction = "row",
        align = "center",
        gap = 8,
        height = H + INSET * 2,
        track,
        ui.action { id = "new-tab", name = "New tab", glyph = "plus", kind = "dashed", on_click = function() tabs.new() end },
    }
end

return M
