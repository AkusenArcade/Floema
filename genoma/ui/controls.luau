--!strict
-- Bioma's controls, as Rizoma has them (ui/controls.luau there), as far as
-- they serve here.
local g = require("@genoma")
local look = require("ui/look")

local M = {}

-- A drawing of the app's own, tinted as Bioma tints its glyphs. `lit()`:
-- in the primary's light; otherwise in one quiet colour.
function M.glyph(name: string, size: number, lit: (() -> boolean)?, quiet: (() -> string)?): any
    local faint = quiet or look.text_muted
    local function on(): boolean return lit == nil or (lit :: any)() end
    return g.svg {
        width = size,
        height = size,
        src = g.dir .. "/icons/" .. name .. ".svg",
        gradient_top = function() return if on() then look.primary_top() else faint() end,
        gradient_bottom = function() return if on() then look.primary_bottom() else faint() end,
    }
end

-- Upper-case, technical, spaced.
function M.label(text: string | () -> string, colour: (() -> string)?): any
    return g.text {
        text = function()
            return string.upper(if type(text) == "function" then text() else text)
        end,
        color = colour or look.text,
        font = look.technical,
        size = look.font_meta,
        weight = 500,
        tracking = look.label_tracking,
    }
end

-- What does one thing: Bioma's buttons (components/choice, and page's dashed
-- one), as tall as the path's capsules. "outline" is the plain one, "filled"
-- the one that does what is asked, "dashed" the one that makes something new.
-- What opens a menu or a cell is a cell itself (M.round).
-- t: id, name, label, glyph, kind, lit() (on, for one that stays), disabled(),
-- present(), bare() (its glyph alone), on_click.
function M.action(t: { [string]: any }): any
    local over = g.signal(false)
    local H = look.action_height
    local dashed = t.kind == "dashed"
    local function off(): boolean return t.disabled ~= nil and t.disabled() end
    local function filled(): boolean return t.kind == "filled" or (t.lit ~= nil and t.lit()) end
    local function worded(): boolean return t.label ~= nil and not (t.bare ~= nil and t.bare()) end
    local function ink(): string
        if filled() then return look.background() end
        return if dashed and over.value and not off() then look.primary() else look.text()
    end
    local function edge(): string
        if filled() then return look.CLEAR end
        if over.value and not off() then return look.primary() end
        return if dashed then g.colour.alpha(look.node(), 0.7) else look.node()
    end
    local node: { [any]: any } = {
        id = t.id,
        role = "button",
        name = t.name or t.label,
        present = t.present,
        height = H,
        min_width = H,
        padding_x = function() return if worded() then 14 else 0 end,
        radius = look.round(H / 2),
        direction = "row",
        align = "center",
        justify = "center",
        gap = 8,
        fill = function() return if filled() then look.primary_top() else look.CLEAR end,
        fill_bottom = function() return if filled() then look.primary_bottom() else look.CLEAR end,
        rim_top = edge,
        rim_bottom = edge,
        opacity = function() return if off() then 0.45 else 1 end,
        transition = { fill = "ui_change", fill_bottom = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change", opacity = "ui_change" },
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = function(button: number)
            if button == 272 and not g.untracked(off) then t.on_click() end
        end,
    }
    if dashed then
        node.dash, node.dash_gap = 3, 3
    end
    if t.glyph then table.insert(node, M.glyph(t.glyph, 16, function() return false end, ink)) end
    if t.label then
        table.insert(node, g.text {
            present = worded,
            text = function() return string.upper(if type(t.label) == "function" then t.label() else t.label) end,
            color = ink,
            font = look.technical,
            size = look.font_action,
            weight = function() return if filled() then 700 else 500 end,
            tracking = 0.04,
        })
    end
    return g.capsule(node)
end

return M
