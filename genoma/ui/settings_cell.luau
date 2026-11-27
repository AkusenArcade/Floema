--!strict
-- Floema's settings (docs/plan.md §5): a round button with Floema's drawing
-- in the window's bottom-right corner, the rule of every app of Bioma's
-- (Rizoma's ui/view_cell.luau), and the cell that buds from it. As in
-- Rizoma, it is always there, and the grid ends above it (shell.luau).
local g = require("@genoma")
local config = require("core/config")
local desktop = require("core/desktop")
local look = require("ui/look")
local ui = require("ui/controls")
local foot_cell = require("ui/foot_cell")

local M = {}

M.open = g.signal(false)

local PAD, LABEL_W, WIDTH = 22, 108, 440

local function row(name: string, control: any, present: (() -> boolean)?): any
    return g.box {
        present = present,
        direction = "row",
        align = "center",
        gap = 12,
        height = 30,
        g.box { width = LABEL_W, ui.label(name) },
        control,
    }
end

-- How much of the window's foot it takes: the grid ends above it.
M.FOOT = look.margin_edge + foot_cell.BUTTON + 8

-- Where its button is.
function M.x(area: { w: number, h: number }): number return area.w - look.margin_edge - foot_cell.BUTTON end

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local SPAN = config.SIZE_MAX - config.SIZE_MIN
    local content = g.box {
        direction = "column",
        align = "stretch",
        gap = look.gap,
        padding = PAD,
        row("Size", g.box {
            direction = "row",
            align = "center",
            gap = 12,
            ui.slider {
                id = "size",
                name = "The size of the letters",
                width = WIDTH - PAD * 2 - LABEL_W - 12 - 40,
                step = 1 / SPAN,
                value = function() return (config.get("font_size") - config.SIZE_MIN) / SPAN end,
                on_move = function(v: number) config.set("font_size", config.SIZE_MIN + math.floor(v * SPAN + 0.5)) end,
            },
            g.box {
                width = 28,
                justify = "end",
                g.text {
                    text = function() return tostring(config.get("font_size")) end,
                    color = look.text,
                    font = look.technical,
                    size = look.font_meta,
                    tabular = true,
                },
            },
        }),
        row("Trail", ui.switch {
            id = "switch-trail",
            name = "The cursor's trail",
            on = function() return config.get("cursor_trail") end,
            on_toggle = function(on: boolean) config.set("cursor_trail", on) end,
        }),
        row("Notify", ui.segmented {
            id = "notify",
            options = {
                { key = "0", label = "Never" },
                { key = "10", label = "10 s" },
                { key = "30", label = "30 s" },
                { key = "60", label = "1 min" },
            },
            current = function() return tostring(config.get("notify_after")) end,
            on_choose = function(key: string) config.set("notify_after", tonumber(key) or 10) end,
        }),
        row("Default", ui.switch {
            id = "switch-default",
            name = "The default terminal",
            on = desktop.is_default,
            on_toggle = desktop.set_default,
        }, desktop.can_be_default),
        -- Without what reads the list, the switch is a choice nobody asks.
        g.box {
            present = function() return desktop.can_be_default() and not desktop.reader.value end,
            padding_left = LABEL_W + 12,
            g.text {
                text = "Opened as the terminal where xdg-terminal-exec is installed.",
                max_width = WIDTH - PAD * 2 - LABEL_W - 12,
                wrap = true,
                color = look.text_faint,
                font = look.expressive,
                size = look.font_secondary,
            },
        },
    }

    return foot_cell.new {
        id = "settings",
        name = "Settings",
        area = area,
        x = function() return M.x(area()) end,
        open = M.open,
        width = WIDTH,
        outside = true,
        content = content,
        button = function(bx: () -> number, by: () -> number): any
            return ui.round {
                id = "settings-button",
                name = "Settings",
                glyph = "floema",
                glyph_size = 20,
                lit = function() return M.open.value end,
                on_click = function() M.open.value = not g.untracked(function() return M.open.value end) end,
                props = {
                    overlay = true,
                    attach = "corner",
                    offset_x = bx,
                    offset_y = by,
                    backdrop_blur = look.glass_blur,
                },
            }
        end,
    }
end

return M
