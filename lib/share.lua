-- One paste that carries what it needs: a level, a run, or both.
--
-- A custom level's run is useless without the level, and a level with no run is
-- still worth sending, so the bundle has two optional sections and a recipient
-- never has to coordinate two pastes. The clipboard form is the same document,
-- deflated and base64ed: `TY1:...` on one line, short enough for a chat message.
--
-- Transport is deliberately NOT this module's business. main.lua decides that a
-- string goes to the clipboard, a file, or (later) an HTTP call; that is the
-- seam a hosted version would plug into.

local levelfmt = require("lib.levelfmt")
local runfmt = require("lib.run")

local M = {}

M.VERSION = 1
M.HEADER = "TOWYARD SHARE "
M.PREFIX = "TY1:"

local function quote(s)
    return '"' .. tostring(s or "user"):gsub('"', '') .. '"'
end

local function strip(s)
    return (tostring(s):gsub("\n+$", ""))
end

function M.bundle(level, run, codec, author)
    if not codec then return nil, "no codec" end
    if not (level or run) then return nil, "nothing to share" end

    local out = { M.HEADER .. M.VERSION, "author " .. quote(author) }
    if level then
        out[#out + 1] = "--- level"
        out[#out + 1] = strip(levelfmt.encode(level))
    end
    if run then
        out[#out + 1] = "--- run"
        out[#out + 1] = strip(runfmt.encode(run, codec))
    end
    return table.concat(out, "\n") .. "\n"
end

function M.code(text, codec)
    if not codec then return nil, "no codec" end
    if type(text) ~= "string" then return nil, "nothing to encode" end
    return M.PREFIX .. codec.encode(codec.compress(text))
end

-- Accepts the text or the code, and never raises on either: a share string is a
-- stranger's input, whether it arrived in a chat message or a dropped file.
function M.unpack(text, codec)
    if type(text) ~= "string" then return nil, "not a document" end
    if not codec then return nil, "no codec" end

    local body = text:match("^%s*(.-)%s*$")
    if body:sub(1, #M.PREFIX) == M.PREFIX then
        local ok, blob = pcall(codec.decode, body:sub(#M.PREFIX + 1))
        if not ok or type(blob) ~= "string" then return nil, "this code is not readable" end
        local ok2, inflated = pcall(codec.decompress, blob)
        if not ok2 or type(inflated) ~= "string" then return nil, "this code is damaged" end
        body = inflated
    end

    local header, author = false, nil
    local sections = {}
    local current = nil

    for raw in body:gmatch("[^\n]+") do
        local line = raw:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line == "--- level" then
            current = "level"
            sections.level = {}
        elseif line == "--- run" then
            current = "run"
            sections.run = {}
        elseif line ~= "" then
            if current then
                sections[current][#sections[current] + 1] = line
            elseif not header then
                if line ~= M.HEADER .. M.VERSION then
                    return nil, "not a share document: " .. line
                end
                header = true
            else
                local who = line:match("^author%s+(.*)$")
                if who then author = who:gsub('^"+', ""):gsub('"+$', "") end
            end
        end
    end

    if not header then return nil, "not a share document" end

    local result = { author = author or "user" }
    if sections.level then
        local lvl, err = levelfmt.decode(table.concat(sections.level, "\n") .. "\n")
        if not lvl then return nil, "the level in this bundle is broken: " .. tostring(err) end
        result.level = lvl
    end
    if sections.run then
        local r, err = runfmt.decode(table.concat(sections.run, "\n") .. "\n", codec)
        if not r then return nil, "the run in this bundle is broken: " .. tostring(err) end
        result.run = r
    end
    if not (result.level or result.run) then return nil, "this bundle has no level and no run" end
    return result
end

return M
