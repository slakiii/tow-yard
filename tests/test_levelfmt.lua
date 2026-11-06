-- The level document: a level must survive a trip through text unchanged, and
-- the text must be the *authored* data -- a size that is already the kind's
-- default is not written out, or every hedge in the campaign starts carrying
-- numbers nobody chose and the file stops reading like the level.

local H = require("tests.helper")
local levels = require("lib.levels")
local levelfmt = require("lib.levelfmt")

local M = { order = {
    "every_shipped_level_round_trips",
    "default_sizes_are_not_written_out",
    "rejects_broken_documents",
    "rejects_a_document_with_too_many_props",
    "accepts_crlf_line_endings",
    "quotes_and_newlines_survive_the_text",
} }

function M.every_shipped_level_round_trips()
    for _, lvl in ipairs(levels.ALL) do
        local text = levelfmt.encode(lvl)
        local back, err = levelfmt.decode(text)
        H.expect(back ~= nil, lvl.name .. ": " .. tostring(err))
        H.expect(levelfmt.encode(back) == text, lvl.name .. ": not byte-stable")
    end
end

function M.default_sizes_are_not_written_out()
    local text = levelfmt.encode(levels.get(1))
    local line
    for l in text:gmatch("[^\n]+") do
        if l:match("^wall building") then line = l end
    end
    H.expect(line ~= nil, "level 1 should still have its clubhouse")
    local n = 0
    for _ in line:gmatch("%S+") do n = n + 1 end
    H.expect(n == 4, "a default-sized prop is kind, x, y -- got: " .. line)
end

-- A broken document must be refused with a reason, not with a traceback and not
-- by being quietly accepted: these files arrive from strangers.
local function with_line(text, prefix, replacement)
    local out, n = text:gsub("\n" .. prefix .. " [^\n]*", "\n" .. replacement)
    H.expect(n >= 1, "fixture: no '" .. prefix .. "' line to replace")
    return out
end

function M.rejects_broken_documents()
    local good = levelfmt.encode(levels.get(1))
    local cases = {
        { "wrong version", function(t) return (t:gsub("^TOWYARD LEVEL 1", "TOWYARD LEVEL 9")) end,
          "bad header" },
        { "unknown key", function(t) return t .. "wallz 5 5\n" end, "unknown key" },
        { "nan coordinate", function(t) return with_line(t, "spawn", "spawn 46 nan 0") end, "finite" },
        { "infinite coordinate", function(t) return with_line(t, "spawn", "spawn 46 1e999 0") end, "finite" },
        { "unknown prop kind", function(t) return with_line(t, "wall building", "wall unicorn 8 33") end,
          "unknown kind" },
        { "kind on the wrong list", function(t) return with_line(t, "cone cone", "cone hedge 33 17.2") end,
          "cannot sit on the cone" },
        { "zero bay tolerance", function(t) return with_line(t, "bay", "bay 22 20 9 4 0 0") end, "tolerance" },
        { "negative bay size", function(t) return with_line(t, "bay", "bay 22 20 -9 4 0 6") end, "bay" },
        { "unbalanced quote", function(t) return with_line(t, "hint", 'hint "no closing quote') end,
          "unbalanced" },
        { "overlong hint", function(t)
            return with_line(t, "hint", 'hint "' .. string.rep("x", 201) .. '"')
        end, "too long" },
        { "tiny bounds", function(t) return with_line(t, "bounds", "bounds 0 0 1 1") end, "bounds" },
        { "zero par", function(t) return with_line(t, "par", "par 0") end, "par" },
        { "wall without h", function(t) return with_line(t, "wall hedge 29 14", "wall hedge 29 14 46") end,
          "w and h together" },
    }
    for _, c in ipairs(cases) do
        local name, mutate, expected = c[1], c[2], c[3]
        local lvl, err = levelfmt.decode(mutate(good))
        H.expect(lvl == nil, name .. ": should have been rejected")
        H.expect(err and err:find(expected, 1, true) ~= nil,
                 name .. ": expected a reason containing '" .. expected .. "', got: " .. tostring(err))
    end
end

function M.rejects_a_document_with_too_many_props()
    local text = levelfmt.encode(levels.get(1))
    local extra = {}
    for i = 1, 2000 do extra[i] = "cone chair " .. (i % 40 + 1) .. " 38" end
    local lvl, err = levelfmt.decode(text .. table.concat(extra, "\n") .. "\n")
    H.expect(lvl == nil, "2000 extra props must be refused, not parsed")
    H.expect(tostring(err):find("too many") ~= nil, "reason should name the cap, got: " .. tostring(err))
end

function M.accepts_crlf_line_endings()
    -- Share files travel between machines and Windows will hand us CRLF.
    local text = levelfmt.encode(levels.get(2))
    local back, err = levelfmt.decode((text:gsub("\n", "\r\n")))
    H.expect(back ~= nil, "a CRLF document must parse: " .. tostring(err))
    H.expect(levelfmt.encode(back) == text, "line endings must not change the level")
end

function M.quotes_and_newlines_survive_the_text()
    local raw = 'He said "back it in"\nnot forward'
    local doc = 'hint "He said \\"back it in\\"\\nnot forward"'
    local text = with_line(levelfmt.encode(levels.get(1)), "hint", doc)
    local lvl, err = levelfmt.decode(text)
    H.expect(lvl ~= nil, "an escaped hint must parse: " .. tostring(err))
    H.expect(lvl.hint == raw, "the hint must come back exactly, got: " .. tostring(lvl.hint))
    H.expect(levelfmt.encode(lvl):find(doc, 1, true) ~= nil, "re-encoding must reproduce the escapes")
end

return M
