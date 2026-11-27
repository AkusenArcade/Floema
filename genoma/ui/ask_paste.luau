--!strict
-- Several lines pasted where the program does not take bracketed paste:
-- each line would run as it arrives, so Floema asks first (docs/plan.md
-- §2). A small cell grows from the cursor, says how many lines and how the
-- first begins; Return or Paste pastes them, Escape or Cancel does not.
-- Every key is its own while it asks.
local g = require("@genoma")
local look = require("ui/look")
local controls = require("ui/controls")

local M = {}

local PAD, W, H = 12, 340, 108

-- `t`: font() (the grid's), cursor() ({ x, y, w, h } in the grid's box, nil
-- when not shown), room() ({ w, h }), paste(text).
function M.new(t: { [string]: any }): (any, any)
    local asked = g.signal(nil :: { text: string, lines: number, x: number, y: number, w: number, h: number }?)
    local grown = g.signal(false)
    local there = g.signal(false)
    local going: any = nil

    local P: { [string]: any } = {}

    function P.is_open(): boolean return g.untracked(function() return there.value end) end

    local function close()
        grown.value = false
        if going then going:stop() end
        going = g.after(look.CLOSE, function()
            going = nil
            there.value = false
            asked.value = nil
        end)
    end

    function P.ask(text: string)
        local c = g.untracked(t.cursor) or { x = PAD, y = PAD, w = 0, h = 0 }
        local _, breaks = string.gsub(text, "\n", "")
        local lines = breaks + (if string.sub(text, -1) == "\n" then 0 else 1)
        if going then going:stop() end
        going = nil
        g.batch(function()
            grown.value = false
            asked.value = { text = text, lines = lines, x = c.x, y = c.y, w = c.w, h = c.h }
            there.value = true
        end)
        g.after(0, function() grown.value = g.untracked(function() return there.value end) end)
    end

    local function paste()
        local a = g.untracked(function() return asked.value end)
        close()
        if a then t.paste(a.text) end
    end

    function P.key(name: string, _: string?, _: any)
        if name == "Return" or name == "KP_Enter" then
            paste()
        elseif name == "Escape" then
            close()
        end
    end

    local function a(): { text: string, lines: number, x: number, y: number, w: number, h: number }
        return asked.value or { text = "", lines = 0, x = 0, y = 0, w = 0, h = 0 }
    end
    local E = look.margin_edge
    local function width(): number return math.min(W, t.room().w - E * 2) end
    local function left(): number return math.clamp(a().x, E, math.max(E, t.room().w - E - width())) end
    local function top(): number
        local below = a().y + a().h + 4
        if below + H <= t.room().h - E then return below end
        return math.max(E, a().y - 4 - H)
    end
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end
    -- How the first line begins: enough to know what it is.
    local function first(): string
        local line = string.match(a().text, "^[^\n]*") or ""
        return if #line > 48 then string.sub(line, 1, 47) .. "…" else line
    end

    local node = g.box {
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        width = function() return t.room().w end,
        height = function() return t.room().h end,
        -- A press beside it is a no.
        g.box {
            overlay = true,
            attach = "corner",
            width = function() return t.room().w end,
            height = function() return t.room().h end,
            on_press = function() close() end,
            on_click = function() end,
        },
        g.capsule {
            name = "Paste several lines?",
            overlay = true,
            attach = "corner",
            offset_x = function() return if grown.value then left() else a().x end,
            offset_y = function() return if grown.value then top() else a().y end,
            width = function() return if grown.value then width() else a().w end,
            height = function() return if grown.value then H else a().h end,
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
                width = function() return width() - PAD * 2 end,
                height = H - PAD * 2,
                direction = "column",
                align = "stretch",
                gap = 6,
                opacity = function() return if grown.value then 1 else 0 end,
                transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
                controls.label(function() return `Paste {a().lines} lines?` end, look.text),
                g.text {
                    text = first,
                    max_width = function() return width() - PAD * 2 end,
                    ellipsize = "end",
                    color = look.text_muted,
                    font = t.font,
                    size = 13,
                },
                g.box { grow = 1 },
                g.box {
                    direction = "row",
                    justify = "end",
                    gap = 8,
                    controls.action { name = "Cancel", label = "Cancel", on_click = close },
                    controls.action { name = "Paste", label = "Paste", kind = "filled", on_click = paste },
                },
            },
        },
    }
    return node, P
end

return M
