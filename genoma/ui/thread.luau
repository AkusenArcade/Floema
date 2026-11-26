--!strict
-- Not used for now (Akusen, 2026-11-26: the path above the grid left out;
-- kept to be thought about again).
-- Where the tab's shell stands, as Rizoma's path (ui/path_bar.luau there),
-- read only: each folder a capsule, each thread the way to the next. A cd
-- into a folder buds a shoot out of the last capsule; coming out, the thread
-- is taken back and the shoot with it. A press on a step opens it in Rizoma.
local g = require("@genoma")
local apps = require("@genoma/apps")
local paths = require("core/paths")
local tabs = require("core/tabs")
local look = require("ui/look")

local M = {}

local H, PAD, THREAD, NAME_MAX = look.action_height, 14, 16, 220
local NODE = 4

type Shoot = { name: string, path: string, leaving: boolean, turn: number }

local function shoots(steps: { paths.Step }, turn: number): { Shoot }
    local out: { Shoot } = {}
    for _, s in steps do table.insert(out, { name = s.name, path = s.path, leaving = false, turn = turn }) end
    return out
end

local function here(): string
    local t = tabs.tab.value
    return if t then t.cwd.value else paths.home
end

local chain = g.signal(shoots(paths.steps(g.untracked(here)), 0))
local clearing: any = nil

local function alive(list: { Shoot }): { Shoot }
    local out: { Shoot } = {}
    for _, s in list do
        if not s.leaving then table.insert(out, s) end
    end
    return out
end

-- The new folder beside the old one: what they share stays, what was added
-- buds, what was left retracts before it goes. Another tab's folder is not a
-- step from this one's: it is simply there.
local seen_in: any = nil
g.watch(here, function(path: string)
    if clearing then clearing:stop() end
    clearing = nil
    local tab = g.untracked(function() return tabs.tab.value end)
    if tab ~= seen_in then
        seen_in = tab
        chain.value = shoots(paths.steps(path), 0)
        return
    end
    local before = alive(g.untracked(function() return chain.value end))
    local after = shoots(paths.steps(path), 0)
    local shared = 0
    while shared < #before and shared < #after and before[shared + 1].path == after[shared + 1].path do
        shared += 1
    end
    for i = shared + 1, #after do after[i].turn = i - shared end
    if shared == #after and #before > shared then
        for i = shared + 1, #before do
            local s = table.clone(before[i])
            s.leaving = true
            s.turn = #before - i + 1
            table.insert(after, s)
        end
        clearing = g.after(look.shoots_back(#before - shared), function()
            clearing = nil
            chain.value = alive(g.untracked(function() return chain.value end))
        end)
    end
    chain.value = after
end)

-- Rizoma, where it is installed.
local function rizoma(): any
    return apps:find("dev.akusen.rizoma") or apps:find("rizoma")
end

function M.open(path: string)
    local app = rizoma()
    if app == nil then return end
    g.activation_token {
        app_id = app.id,
        on_token = function(token: string?) apps:launch(app.id, nil, { path }, token) end,
    }
end

local function name_width(name: string): number
    -- As wide as it is when it is the current one: nothing beside it moves
    -- when it becomes it.
    local w = g.text_width { text = name, font = look.expressive(), size = look.font_secondary, weight = 600 }
    return math.min(math.ceil(w) + 1, NAME_MAX)
end
local function width_of(s: { name: string }): number return name_width(s.name) + PAD * 2 end

-- One step and, inside it, the next: a shape buds out of the one holding it.
local function step(index: number, shoot: () -> any, list: () -> { Shoot }, last: () -> string): any
    local first = g.untracked(shoot)
    local grown = g.signal(index == 1 or first.turn == 0)
    if not g.untracked(function() return grown.value end) then
        g.after(0, function() grown.value = true end)
    end
    local over = g.signal(false)
    local function out(): boolean return grown.value and not shoot().leaving end
    local function current(): boolean return shoot().path == last() end
    local turn = math.clamp(first.turn, 1, look.TURNS)
    local function back(): number return math.clamp(shoot().turn, 1, look.TURNS) end
    local function shape(): string return if out() then "shoot_" .. turn else "shoot_close_" .. back() end
    local function neck(): string return if out() then "neck_" .. turn else "neck_close_" .. back() end
    local function words(): string return if out() then "shoot_words_" .. turn else "content_out" end
    local function width(): number return width_of(shoot()) end

    local node: { [any]: any } = {
        width = width,
        height = H,
        radius = look.round(H / 2),
        fill = look.glass,
        rim_top = function()
            return if current() then look.rim() elseif over.value then look.node() else look.line()
        end,
        rim_bottom = look.line,
        g.box {
            overlay = true,
            attach = "corner",
            width = width,
            height = H,
            role = "button",
            name = "Open in Rizoma",
            align = "center",
            justify = "center",
            cursor = "pointer",
            opacity = function() return if out() then 1 else 0 end,
            transition = { opacity = words },
            on_hover = function(on: boolean) over.value = on end,
            on_press = function() end,
            on_click = function(button: number)
                local s = g.untracked(shoot)
                if button == 272 and not s.leaving and s.name ~= "…" then M.open(s.path) end
            end,
            g.text {
                text = function() return shoot().name end,
                max_width = NAME_MAX,
                ellipsize = "middle",
                color = function() return if current() or over.value then look.text() else look.text_muted() end,
                font = look.expressive,
                size = look.font_secondary,
                weight = function() return if current() then 600 else 400 end,
                transition = { color = "ui_change" },
            },
        },
    }
    if index > 1 then
        node.overlay = true
        node.attach = "right"
        node.offset_x = function() return if out() then THREAD else 0 end
        node.growth = function() return if out() then 1 else 0 end
        -- The neck: soft and wide as it leaves, gone once it is out.
        node.bud = function() return if out() then 0 else H end
        node.transition = { offset_x = shape, growth = shape, bud = neck, rim_top = "ui_change" }
        -- The thread that stays once it has parted, taken back first.
        table.insert(node, g.thread {
            overlay = true,
            attach = "corner",
            offset_x = -THREAD,
            offset_y = H / 2 - NODE / 2,
            width = THREAD,
            height = NODE,
            stroke = look.thread,
            crisp = true,
            node = NODE,
            fill = look.line,
            color = look.node,
            from_x = 0,
            to_x = THREAD,
            from_y = NODE / 2,
            to_y = NODE / 2,
            growth = function() return if out() then 1 else 0 end,
            transition = { growth = function() return if out() then "thread_" .. turn else "thread_close_" .. back() end },
        })
    else
        node.transition = { rim_top = "ui_change" }
    end
    table.insert(node, g.each {
        overlay = true,
        attach = "corner",
        width = width,
        height = H,
        items = function(): { Shoot }
            local s = list()[index + 1]
            return if s then { s } else {}
        end,
        key = function(s) return if s.name == "…" then "…" else s.path end,
        row = function(s, _) return step(index + 1, s, list, last) end,
    })
    return g.capsule(node)
end

-- `room()`: how wide it may be. A deep path keeps where it starts and as
-- many of its last steps as fit; those between are one "…".
function M.new(room: () -> number): any
    local shown = g.computed(function(): { Shoot }
        local list = chain.value
        local all = 0
        for i, s in list do all += width_of(s) + (if i > 1 then THREAD else 0) end
        if all <= room() or #list < 3 then return list end
        local more = width_of { name = "…" } + THREAD
        local used = width_of(list[1]) + more
        local from = #list + 1
        while from > 3 do
            local w = width_of(list[from - 1]) + THREAD
            if used + w > room() and from <= #list then break end
            used += w
            from -= 1
        end
        local out = { list[1], { name = "…", path = list[from - 1].path, leaving = false, turn = 0 } }
        for i = from, #list do table.insert(out, list[i]) end
        return out
    end)
    local function last(): string
        local list = alive(chain.value)
        return if #list > 0 then list[#list].path else ""
    end
    return g.each {
        direction = "row",
        align = "center",
        height = H,
        items = function(): { Shoot } return { shown.value[1] } end,
        key = function(s) return s.path end,
        row = function(s, _) return step(1, s, function() return shown.value end, last) end,
    }
end

return M
