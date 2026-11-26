--!strict
-- The commands, as the shell marks them (OSC 133): where each one's prompt,
-- line and output are, how it ended and how long it took. The lines are the
-- terminal's marks, followed by id: they move with their text when the
-- window's width rewraps it.
local g = require("@genoma")

local M = {}

export type Command = {
    key: number,
    prompt: number,
    command: number?,
    output: number?,
    done: number?,
    -- Where the command's text starts on its line.
    column: number,
    code: number?,
    started: number?,
    ended: number?,
    text: string,
    -- What the program said of its progress (OSC 9;4) while it ran: state
    -- 1 a value, 2 an error, 3 no value known, 4 paused; value 0 to 100.
    progress: { state: number, value: number }?,
}

-- One terminal's commands; `C.mark` is to be given what g.terminal's
-- on_mark is told.
function M.new(term: any): any
    local C: { [string]: any } = {}

    -- The commands, oldest first; `version` moves whenever one changes.
    C.list = {} :: { Command }
    C.version = g.signal(0)
    -- Commands whose output is folded, and the one stood on (moving by command).
    C.folded = g.signal({} :: { [number]: boolean })
    C.stood = g.signal(nil :: number?)
    -- Only the failed ones shown.
    C.failed_only = g.signal(false)

    -- The command under the pointer.
    C.hovered = g.signal(nil :: number?)

    local count = 0

    local function changed() C.version.value += 1 end

    function C.line(id: number?): number?
        if id == nil then return nil end
        return term:mark(id)
    end

    local function forget(c: Command)
        for _, id in { c.prompt, c.command, c.output, c.done } do
            if id then term:forget(id) end
        end
    end

    -- What was typed: the line from where the command starts, and the lines it
    -- went on to, up to its output.
    local function read_text(c: Command): string
        local from, to = C.line(c.command), C.line(c.output)
        if from == nil then return "" end
        local last = if to then math.max(from, to - 1) else from
        local parts: { string } = {}
        for n = from, last do
            local text = term:line(n) or ""
            if n == from then
                local at = utf8.offset(text, c.column + 1)
                text = if at then string.sub(text, at) else ""
            end
            table.insert(parts, text)
            if not term:wrapped(n) and n < last then table.insert(parts, "\n") end
        end
        return (string.gsub(table.concat(parts), "%s+$", ""))
    end

    -- From g.terminal's on_mark.
    function C.mark(kind: string, id: number, line: number, column: number, code: number?)
        local last = C.list[#C.list]
        if kind == "prompt" then
            -- A prompt drawn again (a resize, a cleared line) where the last one
            -- never ran replaces it; one drawn over older commands (a cleared
            -- screen) takes them away.
            if last and last.output == nil then
                forget(last)
                table.remove(C.list)
            end
            local kept: { Command } = {}
            for _, c in C.list do
                local at = C.line(c.prompt)
                if at and at < line then table.insert(kept, c) else forget(c) end
            end
            C.list = kept
            count += 1
            table.insert(C.list, { key = count, prompt = id, column = 0, text = "" })
        elseif last == nil then
            term:forget(id)
            return
        elseif kind == "command" then
            if last.command then term:forget(last.command) end
            last.command = id
            last.column = column
        elseif kind == "output" then
            last.output = id
            last.started = g.now()
            last.text = read_text(last)
        elseif kind == "done" then
            last.done = id
            last.code = code
            last.ended = g.now()
        end
        changed()
    end

    -- From g.terminal's on_progress: the running command's.
    function C.progress(state: number, value: number)
        local last = C.list[#C.list]
        if last == nil or last.output == nil or last.done ~= nil then return end
        last.progress = if state == 0 then nil else { state = state, value = value }
        changed()
    end

    function C.find(key: number?): (Command?, number?)
        for i, c in C.list do
            if c.key == key then return c, i end
        end
        return nil, nil
    end

    -- Whether its line still shows what was typed: a program that clears
    -- the screen or draws over it (Claude Code, a full repaint) leaves the
    -- shell's marks on lines that now say something else.
    function C.intact(c: Command): boolean
        local at = C.line(c.command)
        if at == nil or c.text == "" then return true end
        local text = term:line(at) or ""
        local from = utf8.offset(text, c.column + 1)
        if from == nil then return false end
        local typed = string.match(c.text, "^[^\n]*") or ""
        local shown = string.sub(text, from)
        -- What fits on the line of what was typed, its start.
        local n = math.min(#typed, #shown, 40)
        return n > 0 and string.sub(shown, 1, n) == string.sub(typed, 1, n)
    end

    -- Whether it ran (an empty line given to the shell is not a command).
    function C.ran(c: Command): boolean return c.output ~= nil and c.text ~= "" end

    -- Its lines: from its prompt to the end of its output (or the cursor, while
    -- it runs).
    function C.span(c: Command): (number?, number?)
        local first = C.line(c.prompt)
        if first == nil then return nil, nil end
        local done = C.line(c.done)
        local last = if done then done - 1 else term:cursor().line
        return first, math.max(first, last)
    end

    -- Its output's lines, when it has any.
    function C.output_span(c: Command): (number?, number?)
        local from = C.line(c.output)
        if from == nil then return nil, nil end
        local done = C.line(c.done)
        local to = if done then done - 1 else term:cursor().line
        if to < from then return nil, nil end
        return from, to
    end

    -- The text of its output, lines that wrap joined again.
    function C.output_text(c: Command): string
        local from, to = C.output_span(c)
        if from == nil or to == nil then return "" end
        local parts: { string } = {}
        for n = from, to do
            table.insert(parts, term:line(n) or "")
            if n < to and not term:wrapped(n) then table.insert(parts, "\n") end
        end
        return table.concat(parts)
    end

    -- How long it took, said briefly; "" under a few seconds.
    function C.took(c: Command): string
        if c.started == nil then return "" end
        local s = (c.ended or g.now()) - c.started
        if s < 3 then return "" end
        if s < 60 then return string.format("%.1f s", s) end
        if s < 3600 then return string.format("%d min %d s", s // 60, s % 60) end
        return string.format("%d h %d min", s // 3600, s // 60 % 60)
    end

    function C.toggle_fold(key: number)
        local f = table.clone(g.untracked(function() return C.folded.value end))
        f[key] = if f[key] then nil else true
        C.folded.value = f
    end

    -- The lines the view leaves out: folded outputs, and with only the failed
    -- shown, the commands that did not fail.
    function C.hidden(): { { number } }
        local _ = C.version.value
        local folded = C.folded.value
        local only = C.failed_only.value
        local out: { { number } } = {}
        for i, c in C.list do
            if not C.intact(c) then
                continue
            elseif only and i < #C.list and C.ran(c) and c.code == 0 then
                local a, b = C.span(c)
                if a and b then table.insert(out, { a, b }) end
            elseif folded[c.key] then
                local a, b = C.output_span(c)
                if a and b then table.insert(out, { a, b }) end
            end
        end
        return out
    end

    -- Standing on commands, from the newest that ran: `by` -1 back, 1 forward.
    function C.step(by: number)
        local ran: { Command } = {}
        for _, c in C.list do
            if C.ran(c) and C.intact(c) then table.insert(ran, c) end
        end
        if #ran == 0 then return end
        local at: number? = nil
        local stood = g.untracked(function() return C.stood.value end)
        for i, c in ran do
            if c.key == stood then at = i end
        end
        local i = if at == nil then (if by < 0 then #ran else 1) else math.clamp(at + by, 1, #ran)
        C.stood.value = ran[i].key
        local first = C.line(ran[i].prompt)
        if first then term:reveal(first) end
    end

    return C
end

return M
