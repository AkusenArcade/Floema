--!strict
-- What Ctrl+click opens (docs/plan.md §2): an address in the browser, a
-- folder in Rizoma, a file in the app that opens its kind. What is under
-- the pointer is taken from the line as it is drawn: the word there, without
-- the quotes, brackets and punctuation around it; a path written as a
-- compiler writes it (`src/main.rs:12:5`) is the file.
local g = require("@genoma")
local apps = require("@genoma/apps")

local M = {}

export type Link = { text: string, from: number, to: number, url: boolean }

local OPENING = "[%(%[{<\"'`]"
local CLOSING = "[%)%]}>\"'`,;:%.!?]"

-- The link at column `col` of `text` (columns from 0), or nil.
function M.at(text: string, col: number): Link?
    -- The line as characters, one a column.
    local chars: { string } = {}
    for _, code in utf8.codes(text) do table.insert(chars, utf8.char(code)) end
    local i = col + 1
    if i > #chars or string.match(chars[i], "%s") then return nil end
    local from, to = i, i
    while from > 1 and not string.match(chars[from - 1], "%s") do from -= 1 end
    while to < #chars and not string.match(chars[to + 1], "%s") do to += 1 end
    -- What wraps it is not part of it.
    while from < to and string.match(chars[from], "^" .. OPENING .. "$") do from += 1 end
    while to > from and string.match(chars[to], "^" .. CLOSING .. "$") do to -= 1 end
    if i < from or i > to then return nil end
    local word = table.concat(chars, "", from, to)
    if string.match(word, "^%a[%w+.-]*://[^%s]+$") or string.match(word, "^mailto:[^%s]+@") then
        return { text = word, from = from - 1, to = to - 1, url = true }
    end
    if string.match(word, "^www%.[%w-]+%.[%w.-]+") then
        return { text = "https://" .. word, from = from - 1, to = to - 1, url = true }
    end
    -- A path: with a slash, from home, or a name with an extension.
    if string.find(word, "/", 1, true) or string.sub(word, 1, 1) == "~" or string.match(word, "^[%w_.-]+%.%a[%w]*$") then
        return { text = word, from = from - 1, to = to - 1, url = false }
    end
    return nil
end

local function launch(app_id: string, uris: { string })
    g.activation_token {
        app_id = app_id,
        on_token = function(token: string?) apps:launch(app_id, nil, uris, token) end,
    }
end

local function xdg_open(target: string)
    pcall(function() g.process { command = { "xdg-open", target } } end)
end

-- Opened: an address at once; a path once it is known to be there, from
-- the folder the shell stands in (`cwd`), without the line and column a
-- compiler adds.
function M.open(link: Link, cwd: string)
    if link.url then
        xdg_open(link.text)
        return
    end
    local path = string.gsub(link.text, ":%d+:?%d*:?$", "")
    -- The folder and the path are given as arguments, never written into
    -- the script.
    local SCRIPT = [[
cd -- "$1" 2>/dev/null
p=$2
case $p in "~") p=$HOME ;; "~/"*) p=$HOME/${p#"~/"} ;; esac
if [ -d "$p" ]; then echo dir; elif [ -e "$p" ]; then echo file; else exit 0; fi
realpath -- "$p"
]]
    local kind: string? = nil
    pcall(function()
        g.process {
            command = { "sh", "-c", SCRIPT, "sh", cwd, path },
            on_line = function(line: string)
                if kind == nil then
                    kind = line
                    return
                end
                if kind == "dir" then
                    local rizoma = apps:find("dev.akusen.rizoma") or apps:find("rizoma")
                    if rizoma then launch(rizoma.id, { line }) else xdg_open(line) end
                else
                    xdg_open(line)
                end
            end,
        }
    end)
end

return M
