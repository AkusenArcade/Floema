--!strict
-- The folder's commands (docs/plan.md §6): called by Ctrl+Space at the
-- prompt, a cell grows from the cursor with what makes sense where the shell
-- stands: the project's commands, git as it is now, the commands already run
-- here. Typing filters; choosing one writes it at the prompt, Return there
-- runs it. Every key is the panel's while it is open.
local g = require("@genoma")
local look = require("ui/look")
local folder_commands = require("core/folder_commands")
local paths = require("core/paths")

local M = {}

type Line = { kind: "title" | "item" | "none", key: string, text: string, meta: string? }

local ROW, TITLE, FILTER, RULE, PAD, MIN, MAX = 30, 26, 34, 9, 8, 300, 560
local MONO = 13
-- Between a command and what is said of it (twice: the room between them
-- is a node of its own).
local GAP = 20

-- `t`: font() (the grid's), cursor() (the cursor's cell { x, y, w, h } in the
-- grid's box, nil when not shown), room() ({ w, h } of the grid's box),
-- folder() (where the shell stands), choose(text) (written at the prompt).
function M.new(t: { [string]: any }): any
    local shown = g.signal(nil :: { x: number, y: number, w: number, h: number, folder: string, at: number }?)
    local grown = g.signal(false)
    local there = g.signal(false)
    local groups = g.signal(nil :: { folder_commands.Group }?)
    local filter = g.signal("")
    local on = g.signal(nil :: string?)
    local going: any = nil
    local count = 0
    -- Which side of the cursor it opened on, kept while it is open so that
    -- filtering shrinks it towards the cursor and never moves it across.
    local below = g.signal(true)
    -- How far its list is scrolled, followed and moved by the keys.
    local scrolled = g.signal(0)

    local P: { [string]: any } = {}

    function P.is_open(): boolean return g.untracked(function() return there.value end) end

    function P.close()
        if not g.untracked(function() return there.value end) then return end
        grown.value = false
        if going then going:stop() end
        going = g.after(look.CLOSE, function()
            going = nil
            there.value = false
            shown.value = nil
            groups.value = nil
        end)
    end

    function P.open()
        local c = g.untracked(t.cursor)
        if c == nil then return end
        if going then going:stop() end
        going = nil
        count += 1
        local folder = g.untracked(t.folder)
        local room = g.untracked(t.room)
        local E = look.margin_edge
        local space_below = room.h - E - (c.y + c.h + 4)
        g.batch(function()
            grown.value = false
            on.value = nil
            filter.value = ""
            scrolled.value = 0
            below.value = space_below >= 240 or space_below >= c.y - 4 - E
            shown.value = { x = c.x, y = c.y, w = c.w, h = c.h, folder = folder, at = count }
            there.value = true
        end)
        -- (What comes back after the panel was put away, or from an older
        -- opening, is not shown.)
        local this = count
        folder_commands.read(folder, function(list: { folder_commands.Group })
            if this == count and g.untracked(function() return there.value end) then groups.value = list end
        end)
        g.after(0, function() grown.value = g.untracked(function() return there.value end) end)
    end

    -- What is offered, filtered by what is typed: each word somewhere in
    -- the command, any case.
    local lines = g.computed(function(): { Line }
        local s = groups.value
        local out: { Line } = {}
        if s == nil then return out end
        local words: { string } = {}
        for w in string.gmatch(string.lower(filter.value), "%S+") do table.insert(words, w) end
        local function matches(text: string): boolean
            local lower = string.lower(text)
            for _, w in words do
                if not string.find(lower, w, 1, true) then return false end
            end
            return true
        end
        for _, group in s do
            local kept: { Line } = {}
            for _, item in group.items do
                -- Before anything is typed, only the most used run here.
                if group.key == "history" and #words == 0 and #kept >= folder_commands.RECENT then break end
                if matches(item.text) then
                    table.insert(kept, { kind = "item", key = `{group.key}:{item.text}`, text = item.text, meta = item.meta })
                end
            end
            if #kept > 0 then
                table.insert(out, { kind = "title", key = "title:" .. group.key, text = group.title })
                for _, l in kept do table.insert(out, l) end
            end
        end
        if #out == 0 then
            table.insert(out, { kind = "none", key = "none", text = if #words > 0 then "Nothing matches" else "Nothing here yet" })
        end
        return out
    end)

    -- The row the keys are on: the one chosen, or the first.
    local current = g.computed(function(): Line?
        local first: Line? = nil
        for _, l in lines.value do
            if l.kind == "item" then
                if l.key == on.value then return l end
                if first == nil then first = l end
            end
        end
        return first
    end)

    -- (Its height, below: what the keys keep in view depends on it.)
    local tall: () -> number

    local function walk(by: number)
        local items: { Line } = {}
        for _, l in g.untracked(function() return lines.value end) do
            if l.kind == "item" then table.insert(items, l) end
        end
        if #items == 0 then return end
        local now = g.untracked(function() return current.value end)
        local at = 1
        for i, l in items do
            if now and l.key == now.key then at = i end
        end
        local key = items[(at - 1 + by) % #items + 1].key
        on.value = key
        -- Kept in view: the list scrolled as little as it takes.
        local y = 0
        for _, l in g.untracked(function() return lines.value end) do
            if l.key == key then break end
            y += if l.kind == "title" then TITLE else ROW
        end
        local seen = g.untracked(tall) - PAD * 2 - FILTER - RULE
        local now_y = g.untracked(function() return scrolled.value end)
        if y < now_y then
            scrolled.value = y
        elseif y + ROW > now_y + seen then
            scrolled.value = y + ROW - seen
        end
    end

    local function choose(l: Line?)
        if l == nil or l.kind ~= "item" then return end
        P.close()
        t.choose(l.text)
    end

    -- Every key is the panel's while it is open.
    function P.key(name: string, text: string?, mods: any)
        if name == "Escape" or (mods.ctrl and name == "space") then
            P.close()
        elseif name == "Down" or name == "Tab" then
            walk(1)
        elseif name == "Up" or name == "ISO_Left_Tab" then
            walk(-1)
        elseif name == "Return" or name == "KP_Enter" then
            choose(g.untracked(function() return current.value end))
        elseif name == "BackSpace" then
            local f = g.untracked(function() return filter.value end)
            if mods.ctrl then
                filter.value = ""
            elseif f ~= "" then
                local last = utf8.offset(f, -1)
                filter.value = if last then string.sub(f, 1, last - 1) else ""
            end
            on.value = nil
        elseif mods.ctrl and string.lower(name) == "u" then
            filter.value = ""
            on.value = nil
        elseif text and text ~= "" and not mods.ctrl and not mods.alt and string.byte(text, 1) >= 32 and string.byte(text, 1) ~= 127 then
            filter.value = g.untracked(function() return filter.value end) .. text
            on.value = nil
        end
    end

    local function mono_width(text: string): number
        return g.text_width { text = text, font = t.font(), size = MONO }
    end
    local function meta_width(text: string): number
        return g.text_width { text = string.upper(text), font = look.technical(), size = look.font_meta, weight = 500, tracking = look.label_tracking }
    end
    local function widest(): number
        return math.max(MIN, math.min(MAX, t.room().w - look.margin_edge * 2))
    end
    local width = g.computed(function(): number
        local w = MIN
        local s = groups.value
        if s then
            for _, group in s do
                w = math.max(w, meta_width(group.title) + PAD * 2 + 24)
                for _, item in group.items do
                    local need = mono_width(item.text) + PAD * 2 + 24
                    if item.meta then need += GAP * 2 + meta_width(item.meta) end
                    w = math.max(w, math.ceil(need))
                end
            end
        end
        return math.min(w, widest())
    end)
    local content_h = g.computed(function(): number
        local h = PAD * 2 + FILTER + RULE
        for _, l in lines.value do h += if l.kind == "title" then TITLE else ROW end
        return h
    end)

    local function row(line: () -> Line, _: any): any
        local first = g.untracked(line)
        if first.kind == "title" then
            return g.box {
                height = TITLE,
                direction = "row",
                align = "center",
                padding_x = 12,
                g.text {
                    text = function() return string.upper(line().text) end,
                    color = look.text_faint,
                    font = look.technical,
                    size = look.font_meta,
                    weight = 600,
                    tracking = look.label_tracking,
                },
            }
        end
        if first.kind == "none" then
            return g.box {
                height = ROW,
                direction = "row",
                align = "center",
                padding_x = 12,
                g.text {
                    text = function() return line().text end,
                    color = look.text_faint,
                    font = look.technical,
                    size = look.font_menu,
                    weight = 500,
                },
            }
        end
        local function lit(): boolean
            local c = current.value
            return c ~= nil and c.key == line().key
        end
        return g.capsule {
            role = "button",
            name = first.text,
            width = function() return width.value - PAD * 2 end,
            height = ROW,
            direction = "row",
            align = "center",
            gap = GAP,
            padding_x = 12,
            radius = look.within(PAD),
            cursor = "pointer",
            fill = function() return if lit() then look.chosen() else look.CLEAR end,
            rim_top = look.CLEAR,
            rim_bottom = look.CLEAR,
            transition = { fill = "ui_change" },
            on_hover = function(o: boolean) if o then on.value = g.untracked(line).key end end,
            on_press = function() end,
            on_click = function(button: number) if button == 272 then choose(g.untracked(line)) end end,
            g.text {
                text = function() return line().text end,
                max_width = function()
                    local m = line().meta
                    return width.value - PAD * 2 - 24 - (if m then GAP * 2 + meta_width(m) else 0)
                end,
                ellipsize = "end",
                color = look.text,
                font = t.font,
                size = MONO,
            },
            g.box { grow = 1 },
            g.text {
                present = function() return line().meta ~= nil end,
                text = function() return string.upper(line().meta or "") end,
                color = look.text_faint,
                font = look.technical,
                size = look.font_meta,
                weight = 500,
                tracking = look.label_tracking,
            },
        }
    end

    local E = look.margin_edge
    local function s(): { x: number, y: number, w: number, h: number } return shown.value or { x = 0, y = 0, w = 0, h = 0 } end
    -- As tall as what it offers, up to the room on its side of the cursor.
    tall = function(): number
        local space = if below.value then t.room().h - E - (s().y + s().h + 4) else s().y - 4 - E
        return math.max(PAD * 2 + FILTER + RULE + ROW, math.min(content_h.value, space))
    end
    -- From the cursor, towards where there is room: below it, else above.
    local function left(): number
        return math.clamp(s().x, E, math.max(E, t.room().w - E - width.value))
    end
    local function top(): number
        return if below.value then s().y + s().h + 4 else s().y - 4 - tall()
    end
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end

    -- What is typed, or what typing does; and where the shell stands.
    local filter_row = g.box {
        height = FILTER,
        direction = "row",
        align = "center",
        padding_x = 12,
        gap = 12,
        g.box {
            direction = "row",
            align = "center",
            grow = 1,
            g.text {
                present = function() return filter.value == "" end,
                text = "TYPE TO FILTER",
                color = look.text_faint,
                font = look.technical,
                size = look.font_meta,
                weight = 500,
                tracking = look.label_tracking,
            },
            g.text {
                present = function() return filter.value ~= "" end,
                text = function() return filter.value end,
                color = look.text,
                font = t.font,
                size = MONO,
            },
            -- Where the next letter goes: still, as the grid's cursor.
            g.capsule {
                present = function() return filter.value ~= "" end,
                width = 2,
                height = MONO + 4,
                radius = 1,
                fill = look.primary,
                rim_top = look.CLEAR,
                rim_bottom = look.CLEAR,
            },
        },
        g.text {
            text = function()
                local v = shown.value
                return string.upper(if v then paths.called(v.folder) else "")
            end,
            color = look.text_faint,
            font = look.technical,
            size = look.font_meta,
            weight = 500,
            tracking = look.label_tracking,
        },
    }

    return g.box {
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        width = function() return t.room().w end,
        height = function() return t.room().h end,
        -- A press beside it puts it away, and does nothing else.
        g.box {
            overlay = true,
            attach = "corner",
            width = function() return t.room().w end,
            height = function() return t.room().h end,
            on_press = function() P.close() end,
            on_click = function() end,
        },
        g.capsule {
            name = "The folder's commands",
            overlay = true,
            attach = "corner",
            offset_x = function() return if grown.value then left() else s().x end,
            offset_y = function() return if grown.value then top() else s().y end,
            width = function() return if grown.value then width.value else s().w end,
            height = function() return if grown.value then tall() else s().h end,
            radius = function() return look.shaped(if grown.value then look.radius_panel else 2) end,
            opacity = function() return if grown.value then 1 else 0 end,
            clip = true,
            fill = look.glass_over,
            rim_top = look.rim,
            rim_bottom = look.line,
            backdrop_blur = look.glass_blur,
            transition = {
                offset_x = function() return if grown.value then "cell_open" else "placed" end,
                offset_y = function() return if grown.value then "cell_open" else "placed" end,
                width = timing,
                height = timing,
                radius = timing,
                opacity = timing,
            },
            on_press = function() end,
            on_click = function() end,
            g.box {
                overlay = true,
                attach = "corner",
                offset_x = PAD,
                offset_y = PAD,
                width = function() return width.value - PAD * 2 end,
                height = function() return tall() - PAD * 2 end,
                direction = "column",
                align = "stretch",
                opacity = function() return if grown.value then 1 else 0 end,
                transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
                filter_row,
                g.box {
                    height = RULE,
                    direction = "column",
                    justify = "center",
                    align = "stretch",
                    padding_x = 4,
                    g.capsule {
                        height = 1,
                        crisp = true,
                        radius = 0,
                        fill = function() return g.colour.alpha(look.line(), 0.6) end,
                        rim_top = look.CLEAR,
                        rim_bottom = look.CLEAR,
                    },
                },
                g.box {
                    height = function() return tall() - PAD * 2 - FILTER - RULE end,
                    radius = look.within(PAD),
                    scroll = "y",
                    scroll_y = function() return scrolled.value end,
                    on_scroll = function(_: number, y: number)
                        if g.untracked(function() return scrolled.value end) ~= y then scrolled.value = y end
                    end,
                    clip = true,
                    direction = "column",
                    align = "stretch",
                    g.each {
                        direction = "column",
                        align = "stretch",
                        height = function() return content_h.value - PAD * 2 - FILTER - RULE end,
                        items = function() return lines.value end,
                        key = function(l: Line) return l.key end,
                        row = row,
                    },
                },
            },
        },
    }, P
end

return M
