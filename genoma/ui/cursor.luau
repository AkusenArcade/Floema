--!strict
-- The cursor, as the plan has it (docs/plan.md §5): the block in the
-- primary, the character under it in the background's colour; hollow while
-- the window has not the keys; a beam or an underline when the program asks
-- for one (DECSCUSR). Moving, it leaves a trail as long as the jump: each of
-- its four corners is on a spring of its own, those in front of the move on
-- a quick one, those behind on a slower one, so it stretches from where it
-- was to where it goes and gathers there. Still, it is still: no blink, which
-- would be motion with nothing behind it, and a frame at rest.
local g = require("@genoma")
local look = require("ui/look")

local M = {}

-- `t`: term, pad (the grid's corner), view(), focused(), font, size(),
-- bells() (a count that grows with each bell: a ring leaves the cursor).
function M.new(t: { [string]: any }): any
    local term, PAD = t.term, t.pad
    -- Where it should be, the cell's rectangle in the shape asked for:
    -- x, y, w, h, or nil while it is not shown.
    local function target(): { number }?
        local c = term:cursor()
        local v = t.view()
        local row = term:row(c.line)
        if not c.shown or row == nil or v.cell_width <= 0 then return nil end
        local cw, ch = v.cell_width, v.cell_height
        local x, y = PAD + c.column * cw, PAD + row * ch
        if c.shape == "beam" then return { x, y, math.max(2, math.floor(cw * 0.14 + 0.5)), ch } end
        if c.shape == "underline" then return { x, y + ch - 2, cw, 2 } end
        return { x, y, cw, ch }
    end

    -- The corners, clockwise from the top left: x and y each.
    local corners: { any } = {}
    local first = g.untracked(target) or { 0, 0, 0, 0 }
    local function at(r: { number }): { { number } }
        return { { r[1], r[2] }, { r[1] + r[3], r[2] }, { r[1] + r[3], r[2] + r[4] }, { r[1], r[2] + r[4] } }
    end
    for _, p in at(first) do
        table.insert(corners, { g.animated(p[1]), g.animated(p[2]) })
    end
    local was: { number }? = g.untracked(target)
    g.watch(function()
        local r = target()
        return if r then `{r[1]}:{r[2]}:{r[3]}:{r[4]}` else ""
    end, function()
        local r = g.untracked(target)
        if r == nil then return end
        local goal = at(r)
        -- Appearing, or from nowhere it was seen: at once.
        if was == nil then
            for i, c in corners do
                c[1]:set(goal[i][1])
                c[2]:set(goal[i][2])
            end
            was = r
            return
        end
        local from = was :: { number }
        local dx = (r[1] + r[3] / 2) - (from[1] + from[3] / 2)
        local dy = (r[2] + r[4] / 2) - (from[2] + from[4] / 2)
        local cx, cy = from[1] + from[3] / 2, from[2] + from[4] / 2
        for i, c in corners do
            local now = at(from)[i]
            -- In front of the move, the corner leads; behind, it follows.
            local ahead = (now[1] - cx) * dx + (now[2] - cy) * dy > 0
            local timing = if ahead or (dx == 0 and dy == 0) then "cursor_lead" else "cursor_trail"
            c[1]:set(goal[i][1], timing)
            c[2]:set(goal[i][2], timing)
        end
        was = r
    end)
    g.watch(function() return target() == nil end, function(gone: boolean)
        if gone then was = nil end
    end)

    local function points(): { number }
        local out: { number } = {}
        for _, c in corners do
            table.insert(out, c[1].value)
            table.insert(out, c[2].value)
        end
        return out
    end
    -- Arrived: every corner where it goes.
    local function settled(): boolean
        local r = target()
        if r == nil then return false end
        local goal = at(r)
        for i, c in corners do
            if math.abs(c[1].value - goal[i][1]) > 0.5 or math.abs(c[2].value - goal[i][2]) > 0.5 then return false end
        end
        return true
    end

    -- The bell: a ring leaves the cursor, grows and fades, once a bell. It
    -- is always there, unseen at rest, so that each bell has somewhere to
    -- start from: placed at the cursor at once, then out over `bell`.
    local phase = g.signal("rest")
    if t.bells then
        local seen_bells = g.untracked(t.bells)
        local going: any = nil
        g.watch(t.bells, function(n: number)
            if n == seen_bells then return end
            seen_bells = n
            if going then going:stop() end
            phase.value = "start"
            g.after(0.02, function()
                phase.value = "out"
                going = g.after(look.BELL, function()
                    going = nil
                    phase.value = "rest"
                end)
            end)
        end)
    end
    local RING = 14
    local function out(): number return if phase.value == "out" then RING else 0 end
    local function how(): string return if phase.value == "out" then "bell" else "placed" end
    local ring = g.capsule {
        overlay = true,
        attach = "corner",
        offset_x = function() return (target() or { 0, 0, 0, 0 })[1] - out() end,
        offset_y = function() return (target() or { 0, 0, 0, 0 })[2] - out() end,
        width = function() return (target() or { 0, 0, 0, 0 })[3] + out() * 2 end,
        height = function() return (target() or { 0, 0, 0, 0 })[4] + out() * 2 end,
        radius = function() return if phase.value == "out" then look.shaped(12) else 0 end,
        opacity = function() return if phase.value == "start" then 1 else 0 end,
        fill = look.CLEAR,
        rim_top = look.primary,
        rim_bottom = look.primary,
        transition = { offset_x = how, offset_y = how, width = how, height = how, radius = how, opacity = how },
    }

    return g.box {
        overlay = true,
        attach = "corner",
        present = function() return target() ~= nil end,
        ring,
        g.path {
            overlay = true,
            attach = "corner",
            width = function() return t.view().cell_width * t.view().cols + PAD * 2 end,
            height = function() return t.view().cell_height * t.view().rows + PAD * 2 end,
            points = points,
            fill = function() return if t.focused() then look.primary() else look.CLEAR end,
            stroke = function() return if t.focused() then 0 else 1.2 end,
            color = look.primary,
        },
        -- The character under the block, once it is there.
        g.text {
            overlay = true,
            attach = "corner",
            present = function()
                return t.focused() and term:cursor().shape == "block" and settled()
            end,
            offset_x = function()
                local r = target()
                return if r then r[1] else 0
            end,
            offset_y = function()
                local r = target()
                return if r then r[2] else 0
            end,
            text = function()
                local c = term:cursor()
                local line = term:line(c.line) or ""
                local i = 0
                for _, code in utf8.codes(line) do
                    if i == c.column then return utf8.char(code) end
                    i += 1
                end
                return ""
            end,
            color = look.background,
            font = t.font,
            size = t.size,
        },
    }
end

return M
